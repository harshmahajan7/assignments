# Shopify → OFBiz OMS: Complete Order Import Flow

---

## The Macro Architecture

Before diving into internals, understand the three-layer separation:

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1: INGESTION                                         │
│  Shopify → AWS EventBridge → AWS SQS                        │
│  Shopify → Job Scheduler (batch polling)                    │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│  LAYER 2: INTEGRATION (The Bridge - Moqui)                  │
│  shopify-oms-bridge component                               │
│  - Consumes SQS / Shopify API                               │
│  - Transforms raw JSON → OMS-ready payload                  │
│  - Calls OFBiz REST API                                     │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│  LAYER 3: PROCESSING (OFBiz OMS)                            │
│  - Receives structured payload                              │
│  - Persists to relational data model                        │
│  - Handles post-creation tasks (payments, fulfillment, etc) │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 1 — Ingestion: Two Paths Into the System

### Path A: Real-Time Webhooks via AWS

When a customer places an order on Shopify, Shopify instantly fires an HTTP POST to a registered webhook endpoint. This is the **real-time path**.

```
Customer pays on Shopify
        │
        ▼
Shopify fires orders/create webhook (HTTP POST with JSON body)
        │
        ▼
AWS EventBridge (Event Bus)
  - Receives the raw HTTP event
  - Applies routing RULES (pattern match on event source, type)
  - Routes matching events to targets
        │
        ▼
AWS SQS Queue (e.g., shopify-orders-queue)
  - Stores the message durably
  - Acts as a BUFFER between Shopify and OMS
        │
        ▼
The Bridge (Moqui) polls SQS
  - Picks up messages in batches
  - Passes each message to sync#ShopifyOrder
```

**Why AWS EventBridge?**
EventBridge is not just a forwarder. It's a routing layer. You can have rules like:
- Route `orders/create` to Queue A (new orders)
- Route `orders/cancelled` to Queue B (cancellations)
- Route `refunds/create` to Queue C (refunds)

This way each domain has its own isolated queue.

**Why SQS?**
The OMS is not always instantly available at the speed Shopify sends webhooks (especially during flash sales). SQS acts as a **shock absorber**:
- If OMS is slow → messages wait in queue, nothing is lost
- If OMS crashes → messages stay in queue, retried when OMS is back
- Provides natural backpressure and flow control
- Messages can be retried automatically on failure (via Dead Letter Queues)

**Why NOT hit OMS directly from Shopify?**
Direct webhooks to OMS means:
- If OMS is down, Shopify's retry window is limited (typically 48h, 19 retries)
- You lose ordering guarantees
- Shopify considers a webhook "failed" if you don't return 200 within 5 seconds
- OMS might be under heavy load and can't process fast enough

SQS decouples the reception (must be instant) from the processing (can be slow).

---

### Path B: Job Scheduler (Batch Polling)

This is the **recovery and historical sync path**. A scheduled Moqui job runs on a configured interval (e.g., every 15 minutes) and directly calls the Shopify GraphQL API to fetch orders created/updated since the last run.

**Why does this exist alongside webhooks?**
- Webhooks are "fire and forget" — Shopify doesn't guarantee delivery
- If the bridge was down when a webhook fired, that order is missed
- The job scheduler acts as a safety net
- Also used for initial historical data load (importing all past orders on go-live)

**The MegaQuery — Why GraphQL Here?**

The job scheduler uses a **GraphQL Bulk Operation** (the "MegaQuery"), not the REST API. Here's why:

```
REST API problem:
  GET /orders.json → returns 250 orders per page
  For each order, you need separate calls for:
    - metafields
    - fulfillment orders
    - transactions
  100 orders = potentially 400 API calls
  Shopify rate limit: ~40 requests/second → you hit limits fast

GraphQL solution:
  Single query fetches EVERYTHING at once:
    orders {
      id, name, createdAt, tags,
      customer { id, email, firstName },
      lineItems { id, sku, quantity, price, discountAllocations },
      shippingLines { title, price },
      fulfillments { id, status, lineItems },
      refunds { id, transactions, return { exchangeLineItems } },
      transactions { id, amount, gateway }
    }
  One call = complete data for all orders
```

The GraphQL response is a JSONL file (one JSON object per line) that Shopify generates and gives you a URL to download. The bridge downloads this file and processes each line.

**The `newOrderSync.launchDate` Property**

This is a critical system property. When the new SQS-based flow was introduced, existing orders were already in OMS. The `launchDate` marks the cutover point:
- Orders created **before** `launchDate` → treated as "historical", go through `ShopifyOrderSyncHistory` path
- Orders created **after** `launchDate` → normal new order creation path

This prevents re-importing every historical order every time the job runs.

---

## Part 2 — The Bridge Layer: Moqui (shopify-oms-bridge)

### Entry Point: `sync#ShopifyOrder`

**Service Definition:** `ShopifyOrderServices.xml` line 4
**Script:** `syncShopifyOrder.groovy`

This is the **orchestrator**. Every order — whether it came from SQS or the job scheduler — passes through here. It receives:
- `shopId` — which Shopify store this order belongs to
- `payload` — the full GraphQL order JSON (Map)

The script does NOT create the order directly. It **analyzes** the payload and routes to the correct sub-service. Here's what it does step by step:

```
syncShopifyOrder.groovy
│
├─ 1. EXTRACT IDENTIFIERS
│     - Resolves Shopify GID (gid://shopify/Order/12345) → plain numeric ID
│     - Uses ShopifyHelper.resolveShopifyGid()
│
├─ 2. CHECK SYNC HISTORY (ShopifyOrderHistory entity)
│     - Has this order been seen before?
│     - If NO + order is before launchDate → create ShopifyOrderSyncHistory (historical path)
│
├─ 3. ANALYZE REFUNDS FOR EXCHANGES
│     - Loops through payload.refunds
│     - Checks ShopifyRefundHistory to find UNPROCESSED refunds
│     - If refund has return.exchangeLineItems → collects those line item IDs
│       (these are exchange items, NOT regular items)
│
├─ 4. SEGREGATE LINE ITEMS
│     - Removes exchange line items from mainOrderLineItems
│     - Exchange items get their own separate processing path
│
├─ 5A. NEW ORDER PATH (no sync history)
│     - Strips refunds and refundAgreements from payload
│     - Strips transactions that belong to refunds
│     - Calls create#ShopifyOrder
│
├─ 5B. EXISTING ORDER PATH (sync history found)
│     - Hash-based change detection:
│       compares email, phone, tags, shippingAddress, billingAddress, note
│       using ShopifyHelper.getJsonHash() for complex objects
│     - Checks line item quantities for changes (cancellations)
│     - Only if changes detected → calls update#ShopifyOrder
│
├─ 6. PROCESS FULFILLMENTS
│     - Checks ShopifyFulfillmentHistory for already-processed fulfillments
│     - For each new fulfillment → calls create#ShopifyFulfillment
│
├─ 7. PROCESS REFUNDS & EXCHANGES
│     - For each unprocessed refund → calls RefundServices.process#ShopifyRefund
│     - Exchange items within refund are also processed here
│
└─ 8. PROCESS TRANSACTIONS
      - Checks ShopifyTransactionHistory
      - For new transactions → calls create#OrderPaymentPreferenceFromShopifyTransactions
```

### Why Postman?

During **development and testing**, developers use Postman to:
1. Manually POST a Shopify order JSON directly to the bridge endpoint
2. Test transformation logic without waiting for a real Shopify event
3. Reproduce a specific failed order by re-posting its exact payload
4. Test edge cases (POS orders, exchange orders, zero-dollar orders)

The bridge exposes REST endpoints that accept the same JSON Shopify sends. Postman lets you hit those endpoints directly.

---

## Part 3 — Order Creation: `create#ShopifyOrder`

**Service Definition:** `ShopifyOrderServices.xml` lines 29–140

This service is the **gatekeeper** before actual creation. It:

```
create#ShopifyOrder
│
├─ 1. VALIDATE shop exists (ShopifyShop entity)
├─ 2. EXTRACT shopifyOrderId (legacyResourceId)
├─ 3. IDEMPOTENCY CHECK
│     - Looks up ShopifyShopOrder entity
│     - If order already exists → return error (prevent duplicates)
│
├─ 4. CALL prepare#TransformedShopifyOrderPayload
│     - This is the BIG transformation step (see Part 4)
│     - Returns a normalized orderMap
│
├─ 5. CHECK skipReason
│     - If transformation decided to skip (e.g., blocked tag) → return
│
├─ 6. CALL create#SalesOrder (OFBiz core service)
│     - Passes the normalized orderMap
│     - Returns orderId
│
├─ 7. CREATE ShopifyShopOrder (linking record)
│     - Stores shopId + orderId + shopifyOrderId
│     - This is the bridge between Shopify world and OMS world
│
├─ 8. OIG CHECK (Order Item Group)
│     - If SHOPIFY_OIG_CHECK setting is Y → group items by fulfillment group
│     - Calls group#OrderByItemGroup
│
└─ 9. CUSTOMER CLASSIFICATION
      - If tags match SHOP_ORD_CUST_CLASS mappings
      - Updates customer's PartyClassification
```

---

## Part 4 — The Transformation Engine: `prepare#TransformedShopifyOrderPayload`

**Script:** `prepareTransformedShopifyOrderPayload.groovy` (1170 lines)

This is where every Shopify field is mapped to OMS fields. It builds a single `orderMap` that `create#SalesOrder` understands.

### 4.1 Helper Functions (Lines 23–168)

Before any mapping, helper closures are defined:

| Helper | Purpose |
|--------|---------|
| `getSystemProperty` | Reads config from SystemProperty entity (with cache) |
| `toBigDecimal` | Safe conversion of any value to BigDecimal (financial safety) |
| `parseTimestamp` | Parses Shopify ISO-8601 dates → SQL Timestamp |
| `sanitize` | Strips `<>` HTML chars from strings |
| `normalizeProperties` | Converts Shopify `customAttributes` list → `[key, value]` maps |
| `resolveCountryGeoId` | ISO country code (US) → OFBiz geoId (USA) |
| `resolveStateGeoId` | Province code (CA) → OFBiz stateProvinceGeoId |
| `mapAddress` | Full address block conversion (see 4.3) |
| `getTypeMapping` | Looks up ShopifyShopTypeMapping for dynamic mappings |
| `resolveShopifyLocationFacility` | ShopifyShopLocation.shopifyLocationId → facilityId |
| `mapMoneyAmount` | Handles both flat values and `{amount, shopMoney}` objects |
| `calculateFulfillmentSplit` | Splits qty into fulfilled vs unfulfilled buckets |

### 4.2 Order Header Mapping (Lines 191–290)

```
Shopify Field                    → OMS Field
─────────────────────────────────────────────────────────────
order.id (GID)                   → orderMap.externalId
order.name (#1001)               → orderMap.orderName
order.sourceName                 → orderMap.channel (via ShopifyShopTypeMapping)
                                   e.g., "pos" → "POS_SALES_CHANNEL"
order.currencyCode               → orderMap.currencyCode
order.currentTotalPriceSet       → orderMap.grandTotal
order.createdAt                  → orderMap.orderDate (parsed Timestamp)
order.closedAt / FULFILLED status → orderMap.statusId = "ORDER_COMPLETED"
                                   else "ORDER_CREATED"
ShopifyShop.productStoreId       → orderMap.productStoreId
```

**Tag-Based Order Skipping:**
```groovy
String skipTags = getSystemProperty("ShopifyServiceConfig", "${productStoreId}.skip.order.import.tags")
// e.g., skipTags = "test,internal,do-not-import"
if (tags.any { skipSet.contains(it.toLowerCase()) }) {
    context.skipReason = "Skipped by tag filter"
    return null  // Order never gets created
}
```

### 4.3 Address Mapping (Lines 102–131)

Shopify sends addresses in a flat structure. OFBiz uses geo IDs. The `mapAddress` closure handles this:

```
Shopify address.countryCode ("US")  → resolveCountryGeoId() → "USA"
Shopify address.provinceCode ("CA") → resolveStateGeoId("USA", "CA") → "CA"  (OFBiz Geo record)

Special: address1 ending in "(R)" → additionalPurpose = "HOME_LOCATION"
         address1 ending in "(B)" → additionalPurpose = "WORK_LOCATION"
```

### 4.4 Customer Mapping (Lines 292–308)

```
Shopify customer.legacyResourceId → orderMap.customerExternalId
                                  → orderMap.customerIdentificationType = "SHOPIFY_CUST_ID"
                                  → orderMap.customerIdentificationValue = <id>

create#SalesOrder uses this to:
  1. Look up existing Party by SHOPIFY_CUST_ID identification
  2. If found → reuse existing partyId
  3. If not found → create new Party + Person + PartyIdentification
```

### 4.5 Order Identifications (Lines 358–370)

Three separate identification records are created:

| Type | Value | Purpose |
|------|-------|---------|
| `SHOPIFY_ORD_NO` | `order.number` (e.g., 1001) | Human-readable order number |
| `SHOPIFY_ORD_NAME` | `order.name` (e.g., #1001) | Formatted name with # |
| `SHOPIFY_ORD_ID` | `order.id` resolved GID | Numeric Shopify ID for API calls |

### 4.6 Shipment Method Resolution (Lines 408–445)

```
shippingLines[0].title (e.g., "Standard Shipping")
        │
        ├─ Look up ShopifyShopCarrierShipment (shop-specific mapping)
        │    e.g., "Standard Shipping" → shipmentMethodTypeId: "STANDARD"
        │                               carrierPartyId: "_NA_"
        │
        ├─ Fall back to ProductStoreShipmentMethView (store-level mapping)
        │
        └─ Default: shipmentMethodTypeId = "STANDARD"

Special case: isCashSaleOrder (POS, no shipping address)
        → shipmentMethodTypeId = "POS_COMPLETED"
        → carrierPartyId = "_NA_"
```

### 4.7 Ship Group Bucketing (Lines 447–639)

This is the most complex transformation. Shopify has ONE order with many items. OFBiz models items into **Ship Groups** (groups of items going to same place via same method).

The algorithm:
1. Loops through all `lineItems`
2. For each item, determines: `facilityId`, `shipmentMethodTypeId`, `carrierPartyId`
3. Also calls `calculateFulfillmentSplit()` to split item into:
   - **FULFILLED portion** → statusId: `ITEM_COMPLETED`
   - **UNFULFILLED portion** → statusId: `ITEM_CREATED`
4. Creates a bucket key: `"facilityId|shipMethodId|carrierId|splitType"`
5. Groups items into buckets

```
Example:
  Order has 3 items:
    Item A (qty 2, 1 fulfilled, 1 unfulfilled, standard ship)
    Item B (qty 1, store pickup at Store-NYC)
    Item C (qty 1, 1 fulfilled, standard ship)

  Buckets created:
    "WarehouseA|STANDARD|_NA_|FULFILLED"  → [ItemA(1), ItemC(1)]
    "WarehouseA|STANDARD|_NA_|UNFULFILLED" → [ItemA(1)]
    "Store-NYC|STOREPICKUP|_NA_|UNFULFILLED" → [ItemB(1)]

  Result: 3 Ship Groups in OMS
```

**Pre-Selected Facility via Tags:**
If the order has a tag matching `PRE_SLCTD_FAC_TAG` setting, the system reads `ORD_ITM_PICKUP_FAC` and `ORD_ITM_SHIP_FAC` settings to pre-assign specific facilities to items based on their `customAttributes`.

### 4.8 Product Resolution (Lines 809–874)

For each line item, product lookup follows this waterfall:

```
1. Shopify variant legacyResourceId
        ↓
   Look up ShopifyShopProduct.shopifyProductId
        ↓ (found → productId)

2. If not found: check productStore.productIdentifierEnumId
   - SHOPIFY_PRODUCT_SKU → look up GoodIdentification by SKU
   - SHOPIFY_BARCODE → look up GoodIdentification by UPCA
        ↓ (found → productId)

3. If still not found:
   - Create a PLACEHOLDER Product record
     (productTypeId = FINISHED_GOOD or DIGITAL_GOOD)
   - Create ShopifyShopProduct link
   - Use the new productId
   
4. If no identifier at all → warn and skip item
```

### 4.9 Item-Level Adjustments (Lines 898–948)

```
item.discountAllocations → OrderItemAdjustment (type: EXT_PROMO_ADJUSTMENT, amount: NEGATED)
item.taxLines            → OrderItemAdjustment (type: SALES_TAX, sourcePercentage: rate)
```

For split items, all adjustment amounts are **multiplied by the splitRatio**:
```
If item qty=2, splitQty=1 → splitRatio = 0.5
Tax on item = $10 → Tax on this ship group's portion = $5
```

### 4.10 Order-Level Adjustments (Lines 1044–1113)

```
order.shippingLines[].price          → OrderAdjustment (type: SHIPPING_CHARGES)
order.shippingLines[].taxLines       → OrderAdjustment (type: SHIPPING_SALES_TAX)
discountApplications (SHIPPING_LINE) → OrderAdjustment (type: EXT_SHIP_ADJUSTMENT, NEGATED)
order.totalTipReceivedSet            → OrderAdjustment (type: DONATION_ADJUSTMENT)
```

### 4.11 Exchange Item Association (Lines 1001–1018)

When an item is part of an exchange order:

```groovy
// Shopify puts "original_line_item_id" in customAttributes of exchange line items
def origProp = itemProperties.find { "original_line_item_id".equalsIgnoreCase(it.key) }

// Look up the original item in OMS
def assocItem = ec.entity.find("co.hotwax.order.OrderItemAndShipGroup")
        .condition("orderItemExternalId", origProp.value).one()

// Create association record
itemMap.assocs = [[
    toOrderId: assocItem.orderId,
    toOrderItemSeqId: assocItem.orderItemSeqId,
    orderItemAssocTypeId: "EXCHANGE",
    quantity: assocItem.quantity
]]
```

---

## Part 5 — Entity Mapping: Shopify → OFBiz Data Model

### Order Header

| Shopify Field | OFBiz Entity | Column |
|---------------|-------------|--------|
| `id` (GID resolved) | `OrderHeader` | `externalId` |
| `name` | `OrderHeader` | `orderName` |
| `createdAt` | `OrderHeader` | `orderDate` |
| `currencyCode` | `OrderHeader` | `currencyUom` |
| `currentTotalPriceSet` | `OrderHeader` | `grandTotal` |
| `productStoreId` (via ShopifyShop) | `OrderHeader` | `productStoreId` |
| `sourceName` (mapped) | `OrderHeader` | `salesChannelEnumId` |

### Customer / Party

| Shopify Field | OFBiz Entity | Note |
|---------------|-------------|------|
| `customer.legacyResourceId` | `PartyIdentification.idValue` | `typeId = SHOPIFY_CUST_ID` |
| `customer.firstName` | `Person.firstName` | Created if party doesn't exist |
| `customer.lastName` | `Person.lastName` | |
| `email` | `ContactMech` | `typeId = EMAIL_ADDRESS` |
| `phone` | `ContactMech` | `typeId = TELECOM_NUMBER` |

### Line Items

| Shopify Field | OFBiz Entity | Column |
|---------------|-------------|--------|
| `lineItem.id` (GID resolved) | `OrderItem` | `externalId` |
| `lineItem.quantity` | `OrderItem` | `quantity` |
| `lineItem.price` | `OrderItem` | `unitPrice` |
| `lineItem.variant.sku` | `OrderItem` | `comments` / via `GoodIdentification` |
| Resolved productId | `OrderItem` | `productId` |
| `ITEM_CREATED` / `ITEM_COMPLETED` | `OrderItem` | `statusId` |

### Adjustments

| Shopify Source | `OrderAdjustment.orderAdjustmentTypeId` |
|----------------|----------------------------------------|
| `shippingLines[].price` | `SHIPPING_CHARGES` |
| `shippingLines[].taxLines` | `SHIPPING_SALES_TAX` |
| `lineItem.discountAllocations` | `EXT_PROMO_ADJUSTMENT` |
| `discountApplications` (SHIPPING_LINE) | `EXT_SHIP_ADJUSTMENT` |
| `totalTipReceived` | `DONATION_ADJUSTMENT` |
| `lineItem.taxLines` | `SALES_TAX` |

### Identification Records

| Type ID | Value Source |
|---------|-------------|
| `SHOPIFY_ORD_NO` | `order.number` |
| `SHOPIFY_ORD_NAME` | `order.name` |
| `SHOPIFY_ORD_ID` | `order.id` (resolved GID) |

---

## Part 6 — Post-Creation: Fulfillments, Refunds, Transactions

After the order is created, `syncShopifyOrder.groovy` continues:

### Fulfillments
- Checks `ShopifyFulfillmentHistory` for already-processed IDs
- For each new fulfillment → `create#ShopifyFulfillment`
- This creates `ItemIssuance` records in OFBiz and updates `OrderItem.statusId` to `ITEM_COMPLETED`

### Refunds
- Checks `ShopifyRefundHistory` for already-processed refund IDs
- For each unprocessed refund → `RefundServices.process#ShopifyRefund`
- If the refund has `return.exchangeLineItems` → the exchange order processing is triggered

### Transactions (Payments)
- Checks `ShopifyTransactionHistory`
- For new transactions → `create#OrderPaymentPreferenceFromShopifyTransactions`
- Each Shopify transaction (gateway: `shopify_payments`, `paypal`, etc.) becomes an `OrderPaymentPreference` + `PaymentGatewayResponse`

---

## Part 7 — Full Flow Diagram (End to End)

```
CUSTOMER PLACES ORDER ON SHOPIFY
            │
            ├──────────────────────────────────────┐
            │ Real-time Path                       │ Batch Path
            ▼                                      ▼
    Shopify Webhook                    Scheduled Job (every N min)
    (orders/create)                    calls Shopify GraphQL API
            │                                      │
            ▼                                      │
    AWS EventBridge                                │
    (route by event type)                          │
            │                                      │
            ▼                                      │
    AWS SQS Queue                                  │
    (durable storage)                              │
            │                                      │
            ▼                                      ▼
    Moqui Bridge polls SQS ◄──── GraphQL MegaQuery response (JSONL)
            │
            ▼
    sync#ShopifyOrder  [syncShopifyOrder.groovy]
    │
    ├── Check ShopifyOrderHistory
    ├── Analyze refunds → find exchanges
    ├── Segregate exchange line items
    │
    ├── NEW ORDER?
    │       └── create#ShopifyOrder
    │               └── prepare#TransformedShopifyOrderPayload [1170-line Groovy]
    │                       ├── Tag filter (skip?)
    │                       ├── Channel mapping
    │                       ├── Customer mapping
    │                       ├── Address → GeoId resolution
    │                       ├── Fulfillment split calculation
    │                       ├── Ship group bucketing
    │                       ├── Product lookup / placeholder creation
    │                       ├── Item adjustment mapping
    │                       ├── Exchange association
    │                       └── Order-level adjustment mapping
    │               └── create#SalesOrder [OFBiz core]
    │               └── create ShopifyShopOrder (link record)
    │
    ├── EXISTING ORDER?
    │       └── Hash-compare fields → update#ShopifyOrder (if changed)
    │
    ├── Process fulfillments → create#ShopifyFulfillment
    ├── Process refunds → RefundServices.process#ShopifyRefund
    └── Process transactions → create#OrderPaymentPreferenceFromShopify
```

---

## Part 8 — Key Configuration Entities

| Entity | Purpose |
|--------|---------|
| `ShopifyShop` | Maps `shopId` → `productStoreId`. Root config for each store. |
| `ShopifyShopOrder` | Links `shopifyOrderId` ↔ `orderId`. Prevents duplicate imports. |
| `ShopifyShopProduct` | Links `shopifyVariantId` ↔ OFBiz `productId` |
| `ShopifyShopLocation` | Links `shopifyLocationId` ↔ `facilityId` |
| `ShopifyShopCarrierShipment` | Maps Shopify shipping method title → `shipmentMethodTypeId` |
| `ShopifyShopTypeMapping` | Generic key-value mapping table (channel, product type, etc.) |
| `ShopifyOrderHistory` | Hash-based change tracking for order header and items |
| `ShopifyFulfillmentHistory` | Tracks which fulfillments have been processed |
| `ShopifyRefundHistory` | Tracks which refunds have been processed |
| `ShopifyTransactionHistory` | Tracks which payment transactions have been processed |
| `SystemProperty` (ShopifyServiceConfig) | Per-store config (skip tags, pre-selected facility tags, etc.) |
| `ProductStoreSetting` | SAVE_BILL_TO_INF, DEFAULT_CARRIER, ORD_ITM_PICKUP_FAC, etc. |

---

## Summary of All Services Involved

| Service | File | Role |
|---------|------|------|
| `sync#ShopifyOrder` | `syncShopifyOrder.groovy` | Master orchestrator. Routes to create/update/refund/fulfillment |
| `create#ShopifyOrder` | `ShopifyOrderServices.xml` | Gatekeeper. Idempotency check, calls transformer, calls OFBiz |
| `prepare#TransformedShopifyOrderPayload` | `prepareTransformedShopifyOrderPayload.groovy` | Full field-by-field transformation |
| `create#SalesOrder` | OFBiz OMS core | Actual database persistence of the sales order |
| `create#ShopifyFulfillment` | `ShopifyOrderServices.xml` | Maps Shopify fulfillments → OFBiz ItemIssuance |
| `process#ShopifyRefund` | `RefundServices` | Handles returns, exchanges, financial credits |
| `create#OrderPaymentPreference...` | `ShopifyOrderServices.xml` | Maps Shopify transactions → OFBiz payments |
| `create#ShopifyOrderSyncHistory` | `ShopifyOrderSyncHistoryServices` | Records historical order processing |
| `group#OrderByItemGroup` | `ShopifyOrderHelperServices` | Groups items by fulfillment OIG (optional) |
| `explode#ShopifyOrderItems` | `ShopifyOrderHelperServices` | Explodes bundles into individual items (if configured) |
