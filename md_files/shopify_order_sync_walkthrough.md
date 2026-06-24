# 🛒 Shopify → OMS Order Import & Sync — Complete Walkthrough
### (Hinglish mein, newcomer ke liye)

---

## 🎯 Big Picture — Kya hota hai ek order place hone par?

```
Shopify Store
    │  Customer places order
    ▼
AWS EventBridge  ──►  AWS SQS Queue
    │                       │
    │         (buffered, reliable message queue)
    │                       │
    ▼                       ▼
mantle-shopify-connector   ◄── Job polls SQS every few minutes
    │   SqsOrderImport.xml
    │
    ▼
DataManager (MDM)          ◄── File upload: runtime://datamanager/orders/raw/
    │   configId = SYNC_SHOPIFY_ORDER / UPDATE_SHOPIFY_ORDER
    │
    ▼
shopify-oms-bridge
    │   syncShopifyOrder.groovy
    │   prepareTransformedShopifyOrderPayload.groovy
    │   ShopifyOrderServices.xml → create#ShopifyOrder / update#ShopifyOrder
    │
    ▼
OFBiz / OMS Database
    OrderHeader, OrderItem, OrderContactMech,
    OrderPaymentPreference, OrderItemShipGroup ...
```

---

## 📦 STEP 1 — Shopify se Event aata hai

### Kya hota hai Shopify par?
- Customer order place karta hai → Shopify ek **Webhook** fire karta hai.
- Ya Shopify ka **GraphQL Bulk Query** se orders pull hote hain.
- Dono cases mein event **AWS EventBridge** tak pahunchta hai, jo use **SQS Queue** mein daal deta hai.

### SQS message ka structure (simplified):
```json
{
  "detail": {
    "metadata": { "X-Shopify-Shop-Domain": "harsh-store.myshopify.com" },
    "payload": { "id": "gid://shopify/Order/12345678" }
  }
}
```

> **SQS kyun?** — Agar OMS down bhi ho, message queue mein safe hai. Koi order miss nahi hoga.

---

## 📥 STEP 2 — SQS Polling Job

### File: `mantle-shopify-connector/service/co/hotwax/shopify/order/SqsOrderImport.xml`

### Service A: `consume#SQSOrderMessages`

**Job kab chalta hai?** — Scheduled job, har kuch minutes mein.

**Job kya karta hai?**
1. `sqsTool.receiveMessages(queueName, 10)` — SQS se **10 messages** ek saath uthata hai
2. Har message se `X-Shopify-Shop-Domain` nikalta hai
3. Domain se `SystemMessageRemote` dhundta hai → `shopId` milta hai
4. `orderId` extract karta hai payload se
5. Orders ko group karta hai by `shopId` (`orderIdsByRemotes` map)
6. **`stage#ShopifyOrder`** call karta hai
7. Messages delete karta hai SQS se (confirm karke)

```xml
<set field="messages" from="sqsTool.receiveMessages(queueName, 10)" />
<while condition="messages">
    <!-- extract orderId + shopId -->
    <service-call name="co.hotwax.shopify.order.SqsOrderImport.stage#ShopifyOrder">
        <field-map field-name="orderIdList" from="orderIds"/>
    </service-call>
    <script>sqsTool.deleteMessageBatch(queueName, messages)</script>
    <set field="messages" from="sqsTool.receiveMessages(queueName, 10)" />
</while>
```

---

## 🗂️ STEP 3 — Order Staging

### Service B: `stage#ShopifyOrder` (same file: `SqsOrderImport.xml`)

**Kya karta hai?**

1. Har orderId ke liye `ShopifyOrderHistory` entity check karta hai:
   - **Naya order** → `newOrderIds` list mein
   - **Pehle se exist karta hai** → `updateOrderIds` list mein

2. Har order ka **full detail** Shopify GraphQL se fetch karta hai:
   ```
   co.hotwax.shopify.order.ShopifyOrderServices.get#ShopifyOrderDetails
   ```

3. JSON file banata hai: `runtime://datamanager/orders/raw/ShopifyOrderList_SYNC_SHOPIFY_ORDER_<uuid>.json`

4. File ko **DataManager** ko upload karta hai:
   ```
   co.hotwax.util.UtilityServices.upload#DataManagerFile
   ```
   - New orders → `configId = SYNC_SHOPIFY_ORDER`, `createOrders = true`
   - Update orders → `configId = UPDATE_SHOPIFY_ORDER`, `createOrders = false`

---

## ⚙️ STEP 4 — DataManager (MDM)

### File: `shopify-oms-bridge/data/SOBOrderSyncData.xml`

DataManager ek generic ingestion framework hai. Config se pata chalta hai ki **kaunsi service call karni hai**:

```xml
<co.hotwax.datamanager.DataManagerConfig configId="SYNC_SHOPIFY_ORDER"
    importServiceName="co.hotwax.sob.order.ShopifyOrderServices.sync#ShopifyOrder"
    description="Handles Shopify order create" />

<co.hotwax.datamanager.DataManagerConfig configId="UPDATE_SHOPIFY_ORDER"
    importServiceName="co.hotwax.sob.order.ShopifyOrderServices.sync#ShopifyOrder"
    description="Handles Shopify order updates" />
```

> **Note:** Dono configs same service call karte hain — `sync#ShopifyOrder`. Difference sirf `createOrders` parameter mein hai.

---

## 🔄 STEP 5 — sync#ShopifyOrder (The Brain)

### File: `shopify-oms-bridge/script/co/hotwax/sob/order/syncShopifyOrder.groovy`

Yeh **main orchestrator script** hai. Ek ek order ke liye yeh kaam karta hai:

### Step 5.1 — Shop validate karo
```groovy
def shopifyShop = ec.entity.find("co.hotwax.ShopifyShop")
    .condition("shopId", shopId).useCache(true).one()
String productStoreId = shopifyShop.productStoreId
```

### Step 5.2 — Historical order check
```groovy
def launchDateProperty = // SystemProperty: newOrderSync.launchDate
// Agar order launch date se pehle ka hai → create#ShopifyOrderSyncHistory
```

### Step 5.3 — Refund analysis
- `ShopifyRefundHistory` aur `ShopifyReturnHistory` check karta hai
- Exchange line items alag karta hai main order se

### Step 5.4 — New Order ya Update?
```groovy
def syncHistory = ec.entity.find("co.hotwax.shopify.ShopifyOrderHistory")
    .condition([shopifyOrderId: resolvedOrderId, shopId: shopId]).one()

if (!syncHistory) {
    // ➡️ NEW ORDER → create#ShopifyOrder
} else {
    // ➡️ EXISTING ORDER → Hash comparison → update#ShopifyOrder if changed
}
```

### Step 5.5 — Hash-based Change Detection (Update flow)
```groovy
['email', 'phone', 'note', 'tags', 'shippingAddress',
 'billingAddress', 'customer', 'paymentTerms', 'totalOutstandingSet'].each { field ->
    // String fields: direct compare
    // Object/Array fields: SHA256 hash compare
    if (syncHistory."${field}Hash" != ShopifyHelper.getJsonHash(payload."${field}")) {
        updateFields."${field}" = payload."${field}"
    }
}
// Line item quantity check
// Risk check (riskHash)
```

**Agar kuch bhi change hua** → `update#ShopifyOrder` call

### Step 5.6 — Fulfillments process karo
```groovy
def unprocessedFulfillments = payload.fulfillments?.findAll {
    !(ShopifyHelper.resolveShopifyGid(it.id) in fulfillmentHistory)
}
// create#ShopifyFulfillment for each unprocessed
```

### Step 5.7 — Returns process karo
- OPEN returns → `create#ShopifyInProgressReturn`
- CLOSED returns → `create#ShopifyCompletedReturn`

### Step 5.8 — Transactions process karo
```groovy
def unprocessedTransactions = payload.transactions.findAll {
    !(ShopifyHelper.resolveShopifyGid(it.id) in transactionsHistory)
}
// create#OrderPaymentPreferenceFromShopifyTransactions
```

---

## 🗃️ STEP 6 — Payload Transformation

### File: `shopify-oms-bridge/script/co/hotwax/sob/order/prepareTransformedShopifyOrderPayload.groovy`

**Shopify JSON → OMS format** mein convert karta hai. Key mappings:

| Shopify Field | OMS Field |
|---|---|
| `order.id` (GID) | `orderMap.externalId` |
| `order.name` (#1234) | `orderMap.orderName` + `SHOPIFY_ORD_NAME` identification |
| `order.number` | `SHOPIFY_ORD_NO` identification |
| `order.sourceName` | `channelId` (via `ShopifyShopTypeMapping`) |
| `order.currentTotalPriceSet` | `orderMap.grandTotal` |
| `order.createdAt` | `orderMap.orderDate` |
| `order.displayFulfillmentStatus` == FULFILLED | `statusId = ORDER_COMPLETED` |
| `order.customer.legacyResourceId` | `customerExternalId` |
| `order.shippingAddress` | `shipTo.postalAddress` (mapped via `mapAddress`) |
| `order.billingAddress` | `billTo.postalAddress` (if SAVE_BILL_TO_INF = Y) |
| `shippingLines[0].title` | `shipmentMethodTypeId` (via `ShopifyShopCarrierShipment`) |
| `lineItem.quantity` / `unfulfilledQuantity` | Split into FULFILLED + UNFULFILLED ship groups |
| `order.tags` | Order notes + `orderAttributes` |
| `order.customAttributes` | `orderAttributes` |

### Ship Group Logic:
```groovy
// Har line item ke liye:
// 1. Fulfilled qty → ITEM_COMPLETED status, POS_COMPLETED method
// 2. Unfulfilled qty → ITEM_CREATED status, STANDARD/STOREPICKUP method
// Key = "facilityId|shipmentMethod|carrierPartyId|splitType"
String shipGroupKey = "${bucketFacilityId}|${shipMethodForGroup}|${carrierPartyId}|${splitType}"
```

---

## 🏗️ STEP 7 — OMS mein Order Create

### File: `shopify-oms-bridge/service/co/hotwax/sob/order/ShopifyOrderServices.xml`
### Service: `create#ShopifyOrder`

**OFBiz entities mein data jaata hai:**

```
OrderHeader          ← externalId, grandTotal, statusId, orderDate, channel
OrderItem            ← productId, quantity, unitPrice, statusId
OrderItemShipGroup   ← facilityId, shipmentMethodTypeId, carrierPartyId
OrderContactMech     ← shipTo address, billTo address, email, phone
OrderPaymentPreference ← payment method, amount
Party / Person       ← customer create/find
PartyIdentification  ← SHOPIFY_CUST_ID
```

**Customer consolidation logic:**
1. `customerExternalId` se existing party dhundho
2. Email/phone se dhundho
3. Nahi mila → naya `Person` party banao

**ShopifyOrderHistory create (after successful OMS order creation):**
```groovy
// Saare hashes save karo for future change detection:
// noteHash, tagsHash, shippingAddressHash, billingAddressHash,
// customerHash, paymentTermsHash, lineItemsHash, riskHash...
```

---

## 📊 Entities — Kahan kya save hota hai

### File: `shopify-oms-bridge/entity/OrderSyncEntities.xml`

```
ShopifyOrderHistory        ← Main sync tracker (hashes + processedDate)
├── shopId (PK)
├── shopifyOrderId (PK)
├── noteHash               ← SHA256 of order note
├── tagsHash               ← SHA256 of tags array
├── shippingAddressHash    ← SHA256 of shipping address
├── billingAddressHash     ← SHA256 of billing address
├── customerHash           ← SHA256 of customer object
├── lineItemsHash          ← SHA256 of line items
├── riskHash               ← SHA256 of risk block
└── processedDate

ShopifyTransactionHistory  ← Processed payment transactions
├── shopId, shopifyOrderId, shopifyTransactionId (PK)
└── status, processedDate

ShopifyRefundHistory       ← Processed refunds
├── shopId, shopifyOrderId, shopifyRefundId (PK)
└── createdDate, processedDate

ShopifyReturnHistory       ← Return lifecycle tracking
├── shopId, shopifyOrderId, shopifyReturnId (PK)
├── returnId, returnStatusId
├── inProgressProcessedDate
├── completedProcessedDate
└── processedDate

ShopifyOrderItemHist       ← Per line item quantity tracking
├── shopId, shopifyOrderId, shopifyLineItemId (PK)
└── quantity, processedDate

ShopifyFulfillmentHistory  ← Processed fulfillments
├── shopId, shopifyOrderId, fulfillmentId (PK)
└── processedDate
```

---

## 🔧 Jobs & Config

### File: `shopify-oms-bridge/data/SOBServiceJobData.xml`

| Job Name | Service | Cron | Purpose |
|---|---|---|---|
| `queue_ShopifyOrderSync` | `queue#FeedSystemMessage` | every 5 min | GraphQL-based order sync |
| `sync_ShopifyOrderHistory` | `sync#ShopifyOrderHistory` | every 5 min | Bulk order history backfill |
| `generate_OMSFulfillmentFeed_Shopify` | `queue#FeedSystemMessage` | hourly | OMS → Shopify fulfillment updates |
| `consume_AllReceivedSystemMessages_frequent` | Moqui system | every 15 min | Process queued messages |

> **`paused="Y"`** — Saare jobs by default paused hote hain. Client ke setup par enable karte hain.

---

## 🧑 EXAMPLE — Harsh ne Nike Shoes order kiya

**Scenario:** Harsh → harsh-store.myshopify.com → Nike Air Max 270, Qty: 1, ₹8,000

### Timeline:

**T=0 sec** — Harsh "Place Order" click karta hai Shopify par.
- Shopify Order ID: `gid://shopify/Order/55001234` (legacyId: `55001234`)
- Order Name: `#1042`

**T=1 sec** — Shopify Webhook fire hota hai → AWS EventBridge → SQS Queue mein message

```json
{
  "detail": {
    "metadata": {"X-Shopify-Shop-Domain": "harsh-store.myshopify.com"},
    "payload": {"id": "55001234"}
  }
}
```

**T=3 min** — `consume#SQSOrderMessages` job chalta hai:
- `shopDomain = "harsh-store.myshopify.com"`
- `SystemMessageRemote` → `shopId = "HARSH_STORE"`
- `orderId = "55001234"`
- `stage#ShopifyOrder` call hoti hai

**T=3 min 5 sec** — `stage#ShopifyOrder`:
- `ShopifyOrderHistory` check → **nahi mila** → `newOrderIds = ["55001234"]`
- GraphQL se full order details fetch: transactions, line items, fulfillments, addresses
- JSON file: `runtime://datamanager/orders/raw/ShopifyOrderList_SYNC_SHOPIFY_ORDER_abc123.json`
- DataManager upload: `configId=SYNC_SHOPIFY_ORDER, createOrders=true`

**T=3 min 10 sec** — DataManager → `sync#ShopifyOrder` call:
- `ShopifyOrderHistory` → nahi mila → new order confirmed
- No historical order (createdAt > launchDate)
- No refunds, no fulfillments yet
- `create#ShopifyOrder` call

**T=3 min 15 sec** — `prepareTransformedShopifyOrderPayload.groovy`:
```
shopifyOrderId  = "55001234"
orderName       = "#1042"
channelId       = "WEB_SALES_CHANNEL"  (sourceName=web)
grandTotal      = 8000.00
orderDate       = 2025-06-24T10:30:00Z
statusId        = "ORDER_CREATED"
facilityId      = "_NA_"  (no pre-selected facility)
shipmentMethod  = "STANDARD"
customer:
  firstName     = "Harsh"
  lastName      = "Mahajan"
  email         = harsh@example.com
  customerExternalId = "CUST_9876"
shippingAddress:
  address1      = "123 MG Road"
  city          = "Bangalore"
  postalCode    = "560001"
  countryGeoId  = "IND"
lineItems:
  [Nike Air Max 270, qty=1, price=8000, unfulfilledQty=1]
  → shipGroup: "_NA_|STANDARD|_NA_|UNFULFILLED"
```

**T=3 min 20 sec** — OFBiz mein records bante hain:
```
OrderHeader:
  orderId        = "ORD-10042"
  externalId     = "55001234"
  statusId       = "ORDER_CREATED"
  grandTotal     = 8000.00

OrderItem:
  orderId        = "ORD-10042"
  orderItemSeqId = "00001"
  productId      = "NIKE-AIR-MAX-270"
  quantity       = 1.0
  unitPrice      = 8000.00
  statusId       = "ITEM_CREATED"

OrderItemShipGroup:
  facilityId           = "_NA_"
  shipmentMethodTypeId = "STANDARD"
  carrierPartyId       = "_NA_"

OrderContactMech:
  contactMechPurposeTypeId = "SHIPPING_LOCATION"
  → PostalAddress: 123 MG Road, Bangalore, 560001, IND

OrderPaymentPreference:
  paymentMethodTypeId = "EXT_SHOP_MANUAL"
  maxAmount           = 8000.00
  statusId            = "PAYMENT_RECEIVED"

Party / Person:
  partyId    = "PARTY-5678"
  firstName  = "Harsh", lastName = "Mahajan"

PartyIdentification:
  partyId                = "PARTY-5678"
  partyIdentificationTypeId = "SHOPIFY_CUST_ID"
  idValue                = "9876"
```

**T=3 min 25 sec** — `ShopifyOrderHistory` mein entry:
```
shopId          = "HARSH_STORE"
shopifyOrderId  = "55001234"
noteHash        = null (no note)
tagsHash        = SHA256([])
shippingAddressHash = SHA256({address1:..., city:..., ...})
customerHash    = SHA256({firstName: Harsh, ...})
lineItemsHash   = SHA256([{id:..., qty:1}])
processedDate   = 2025-06-24T10:33:25Z
```

**Order complete! ✅ Harsh ka order OMS mein aa gaya.**

---

## 🔄 Update Scenario — Harsh address change karta hai

- Shopify webhook → SQS → `consume#SQSOrderMessages`
- `stage#ShopifyOrder`:
  - `ShopifyOrderHistory` → **mila!** → `updateOrderIds`
  - `configId = UPDATE_SHOPIFY_ORDER`, `createOrders = false`
- `syncShopifyOrder.groovy`:
  - `syncHistory` → exist karta hai → **update flow**
  - `shippingAddressHash` compare:
    - Old hash ≠ New hash → `updateFields.shippingAddress = newAddress`
  - `update#ShopifyOrder` call
  - `OrderContactMech` update → naya address save
  - `ShopifyOrderHistory` update → new hash save

---

## 🏭 Alternate Sync Path — GraphQL Bulk Sync

`sync_ShopifyOrderHistory` job (every 5 min) ek alag path hai:

```
ServiceJob: sync_ShopifyOrderHistory
    → sync#ShopifyOrderHistory service
    → SystemMessageType: BulkOrderHistoryQuery
    → GraphQL BulkOrderHistoryQuery.ftl → Shopify API
    → Shopify returns downloadable JSONL file
    → store#BulkOrderHistoryResult → download + parse
    → DataManager: configId=BULK_ORDER_HISTORY
    → create#ShopifyOrderSyncHistory (per order)
```

**Yeh kab use hota hai?** — Initial data migration ya gap reconciliation ke liye.

---

## 📁 Key Files Summary

| File | Location | Purpose |
|---|---|---|
| `SqsOrderImport.xml` | `mantle-shopify-connector/service/co/hotwax/shopify/order/` | SQS polling + staging |
| `syncShopifyOrder.groovy` | `shopify-oms-bridge/script/co/hotwax/sob/order/` | Main sync orchestrator |
| `prepareTransformedShopifyOrderPayload.groovy` | same | Shopify → OMS mapping |
| `ShopifyOrderServices.xml` | `shopify-oms-bridge/service/co/hotwax/sob/order/` | create/update OMS order |
| `ShopifyOrderMappingServices.xml` | same | fulfillment/payment mapping |
| `OrderSyncEntities.xml` | `shopify-oms-bridge/entity/` | ShopifyOrderHistory + related |
| `SOBOrderSyncData.xml` | `shopify-oms-bridge/data/` | DataManagerConfig definitions |
| `SOBServiceJobData.xml` | same | Job scheduling config |

---

## 🧠 Important Concepts — Quick Reference

| Concept | Explanation |
|---|---|
| **SQS** | Buffer queue — order miss nahi hoga even if OMS down hai |
| **EventBridge** | Shopify se AWS tak event routing |
| **DataManager** | Generic file-based ingestion framework (configId se service decide hoti hai) |
| **ShopifyOrderHistory** | "Memory" of the system — kya process hua, kya change hua |
| **Hash Comparison** | SHA256 of JSON fields — unnecessary DB updates avoid karne ke liye |
| **shopId** | Shopify store ka unique ID — multi-tenant support ke liye |
| **GID** | `gid://shopify/Order/55001234` — Shopify ka GraphQL ID format |
| **resolveShopifyGid()** | GID se numeric ID nikalta hai |
| **createOrders flag** | `true` = new orders create karo, `false` = sirf updates |
| **_NA_** | Virtual/unknown facility — real facility assign nahi hua yet |

---

*Document prepared for 2-hour presentation session — HotWax Commerce Shopify Order Sync Flow*
