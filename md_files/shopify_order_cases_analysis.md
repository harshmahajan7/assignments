# Shopify Order Cases — Complete Reference

> Analysis based on `JSON_Example/` files and `prepareTransformedShopifyOrderPayload.groovy`

---

## Order Cases Overview

| # | Case | Shopify JSON File | `sourceName` | `retailLocation` | `shippingLines.code` |
|---|------|-------------------|-------------|-----------------|---------------------|
| 1 | **Online Order** | `M435381_STANDARD` | `web` | `null` | `STANDARD` |
| 2 | **Store Pickup (BOPIS)** | `M435382_STOREPICKUP` | `web` | `null` | `STOREPICKUP` |
| 3 | **Sand Sale** | `M435334_SANDSALE` | `pos` | `{ legacyResourceId }` | `Free Expedited` |
| 4 | **POS Completed** | `M435367_POS` | `pos` | `{ legacyResourceId }` | *(empty array)* |
| 5 | **Mix Card (POS)** | *(POS + partial ship)* | `pos` | `{ legacyResourceId }` | *(mixed items)* |

---

## A. Identifiers — How to Identify Order Type

### A.1 In Shopify JSON

#### `sourceName` Field
```
orderDetails.sourceName
```
| Value | Meaning |
|-------|---------|
| `"web"` | Online order (Standard or BOPIS) |
| `"pos"` | POS-originated order (Sand Sale, POS Completed, Mix Card) |

#### `retailLocation` Field
```
orderDetails.retailLocation: { legacyResourceId, id }
```
| Value | Meaning |
|-------|---------|
| `null` | Web/Online order — no physical POS location |
| `{ legacyResourceId: "87821025411", id: "gid://shopify/Location/..." }` | POS order — maps to OMS Facility |

#### `shippingLines[0].code` Field
```
orderDetails.shippingLines[0].code
```
| Value | Order Type |
|-------|-----------|
| `"STANDARD"` | Online / Standard ship |
| `"STOREPICKUP"` | BOPIS / Store Pickup |
| `"Free Expedited"` | Sand Sale (POS with ship-to-customer) |
| *(empty array)* | POS Completed / Cash Sale |

#### `displayFulfillmentStatus` Field
```
orderDetails.displayFulfillmentStatus
```
| Value | Order Type |
|-------|-----------|
| `"UNFULFILLED"` | Online, BOPIS, Sand Sale |
| `"FULFILLED"` | POS Completed |

#### `shippingAddress` Field
```
orderDetails.shippingAddress
```
| Value | Meaning |
|-------|---------|
| `null` | Cash Sale / POS Completed (no shipping) |
| Object | All other types |

---

### A.2 In OMS (Derived by Groovy)

#### `orderMap.channel` (maps to `OrderHeader.salesChannelEnumId`)

```groovy
// Line 219-220 in groovy:
def channelSource = order.sourceName  // "pos" or "web"
def channelId = getTypeMapping("SHOPIFY_ORDER_SOURCE", channelSource?.toString(), "UNKNWN_SALES_CHANNEL")
```

| Shopify `sourceName` | OMS `channel` / `salesChannelEnumId` |
|---------------------|--------------------------------------|
| `web` | `WEB_SALES_CHANNEL` *(mapped)* |
| `pos` | `POS_SALES_CHANNEL` *(mapped)* |

**How OMS knows it's POS:** `orderMap.channel == "POS_SALES_CHANNEL"`

#### `orderMap.statusId` (maps to `OrderHeader.statusId`)

```groovy
// Lines 273-280:
def orderStatusId = "ORDER_CREATED"
if (order.closedAt || order.displayFulfillmentStatus == 'FULFILLED') {
    orderStatusId = "ORDER_COMPLETED"
}
orderMap.statusId = orderStatusId
```

| OMS `statusId` | Applies To |
|---------------|-----------|
| `ORDER_CREATED` | Online, BOPIS, Sand Sale |
| `ORDER_COMPLETED` | POS Completed (FULFILLED), Mix Card (all items fulfilled) |

#### Boolean Flags (Internal Groovy — not persisted directly, drive routing logic)

```groovy
// Lines 223-228:
boolean isCashSaleOrder = isShippingAddressEmpty && "POS_SALES_CHANNEL".equals(channelId)

boolean isMixedCartPOSOrder = "POS_SALES_CHANNEL".equals(channelId)
        && !isShippingAddressEmpty
        && (!fulfillmentStatusText?.equals("FULFILLED"))
```

| Flag | True When | Order Case |
|------|-----------|------------|
| `isCashSaleOrder` | `sourceName=pos` + `shippingAddress=null` | **POS Completed** |
| `isMixedCartPOSOrder` | `sourceName=pos` + `shippingAddress≠null` + status≠FULFILLED | **Mix Card / Sand Sale** |

#### `OrderItemShipGroup.shipmentMethodTypeId` — The Strongest OMS Identifier

| OMS ShipMethodTypeId | Order Case |
|---------------------|-----------|
| `STANDARD` | Online Order |
| `STOREPICKUP` | BOPIS / Store Pickup |
| `POS_COMPLETED` | POS Completed & fulfilled part of Mix Card |
| `STANDARD` or mapped | Sand Sale (POS + ship out) |

---

## B. Entity Mappings — OrderAttribute, OrderItemAttribute, OrderItemShipGroup

---

### B.1 `OrderAttribute` ← `orderDetails.customAttributes` + system fields

Populated from Groovy lines 327–348:

```groovy
def orderAttributes = []
// System attributes:
if (order.userId || order.staffMember?.id) {
    orderAttributes.add([attrName: "shopify_user_id", attrValue: ...])
}
// All order-level customAttributes become OrderAttributes:
noteAttributes?.each { noteAttr ->
    orderAttributes.add([attrName: key, attrValue: value])
}
```

#### Mapping Table

| OMS `OrderAttribute.attrName` | Shopify JSON Source | Example Value |
|------------------------------|---------------------|---------------|
| `shopify_user_id` | `order.userId` / `order.staffMember.id` | POS staff ID |
| `polar_attr` | `orderDetails.customAttributes[key="polar_attr"]` | Base64 session blob |
| `_layers_session_id` | `orderDetails.customAttributes[key="_layers_session_id"]` | `"48b412f6-..."` |
| `_em_device_id` | `orderDetails.customAttributes[key="_em_device_id"]` | `"0xb18311c4..."` |
| `_em_nav_id` | `orderDetails.customAttributes[key="_em_nav_id"]` | `"0x07a81a49..."` |
| `_em_session_id` | `orderDetails.customAttributes[key="_em_session_id"]` | `"0xf5adbad6..."` |
| `__tolstoyAnonymousId` | `orderDetails.customAttributes[key="__tolstoyAnonymousId"]` | UUID |
| `Gift Wrap Option` | `orderDetails.customAttributes[key="Gift Wrap Option"]` | `"Gift Wrap Items Together"` |

> **Rule:** Every `key/value` pair in `orderDetails.customAttributes[]` → one `OrderAttribute` row  
> **Max lengths enforced:** `attrName` truncated to 59 chars, `attrValue` to 999 chars

#### Per-Order-Type `customAttributes`

| Order Type | `customAttributes` Contents |
|-----------|----------------------------|
| **Online Order** | tracking/session keys + `Gift Wrap Option` |
| **Store Pickup** | tracking/session keys + `Gift Wrap Option: "Gift Wrap Items Separately"` |
| **Sand Sale** | `[]` (empty) |
| **POS Completed** | `[]` (empty) |
| **Mix Card** | Same as POS Completed (typically empty at order level) |

---

### B.2 `OrderItemAttribute` ← `lineItem.customAttributes`

Populated from Groovy lines 952–985:

```groovy
def orderItemAttributes = []
def itemProperties = normalizeProperties(item.customAttributes)

// Special OMS flags first:
if (isPreorderItem) → attrName: "PreOrderItemProperty"
if (isBackorderItem) → attrName: "BackOrderItemProperty"
if (storePickupProperty found in props) → attrName: "StorePickupItemProperty"

// Then ALL customAttributes on the line item:
itemProperties.each { prop ->
    orderItemAttributes.add([attrName: prop.key, attrValue: prop.value])
}
```

#### Mapping Table

| OMS `OrderItemAttribute.attrName` | Shopify JSON Source | Example Value | Order Type |
|----------------------------------|---------------------|---------------|-----------|
| `Delivery Method` | `lineItem.customAttributes[key="Delivery Method"]` | `"Ship to Me"` | Online |
| `Gift Wrap` | `lineItem.customAttributes[key="Gift Wrap"]` | `"With Love"` | Online / BOPIS |
| `Delivery Method` | `lineItem.customAttributes[key="Delivery Method"]` | `"Pick Up at Irvine Spectrum, 864 Spectrum Center Drive"` | BOPIS |
| `_pickupstore` | `lineItem.customAttributes[key="_pickupstore"]` | `"29"` (facilityId) | **BOPIS** |
| `_layers_attribution` | `lineItem.customAttributes[key="_layers_attribution"]` | ULID token | BOPIS / Online |
| `StorePickupItemProperty` | Derived — when `_pickupstore` key found | System property value | BOPIS |
| `PreOrderItemProperty` | Derived — product in preorder category | Mapped tag value | Any |
| `BackOrderItemProperty` | Derived — product in backorder category | Mapped tag value | Any |

#### Per-Order-Type `lineItem.customAttributes`

| Order Type | `lineItem.customAttributes` Contents |
|-----------|--------------------------------------|
| **Online Order** | `Delivery Method: "Ship to Me"`, `Gift Wrap: "With Love"` |
| **Store Pickup** | `Delivery Method: "Pick Up at..."`, `_pickupstore: "29"`, `_layers_attribution: ...`, `Gift Wrap: "With Love"` |
| **Sand Sale** | `[]` (empty) |
| **POS Completed** | `[]` (empty) |
| **Mix Card** | Depends on the item — ship items get `Delivery Method: Ship to Me`, pickup items get `_pickupstore` |

> **Key BOPIS Identifier in OMS ItemAttr:** `_pickupstore` with facilityId value (e.g. `"29"`)

---

### B.3 `OrderItemShipGroup` (Ship Group entity) ← Multi-field derivation

The ship group is built by the bucket key:  
```
"{facilityId}|{shipmentMethodTypeId}|{carrierPartyId}|{splitType}"
```

Fields mapped per order type:

---

#### Case 1: Online Order (Standard Shipping)

**Shopify signals:** `sourceName=web`, `retailLocation=null`, `shippingLines[0].code=STANDARD`

| `OrderItemShipGroup` Field | Value | Source in Shopify JSON |
|---------------------------|-------|------------------------|
| `shipmentMethodTypeId` | `STANDARD` | Mapped from `shippingLines[0].title = "Standard"` via `ShopifyShopCarrierShipment` |
| `carrierPartyId` | From ProductStore setting | Config |
| `facilityId` | `defaultFacilityId` or `_NA_` | `productStore.inventoryFacilityId` |
| `orderFacilityId` | `null` | No retail location |
| `maySplit` | `Y` / `N` | `productStore.allowSplit` |
| **shipTo** → `postalAddress` | Full shipping address | `orderDetails.shippingAddress` |
| **shipTo** → `phoneNumber` | Phone | `orderDetails.shippingAddress.phone` |
| **shipTo** → `email` | Email | `orderDetails.email` |
| Item `statusId` | `ITEM_CREATED` | `unfulfilledQuantity > 0` |

```json
// Shopify (STANDARD order):
"sourceName": "web",
"retailLocation": null,
"shippingLines": [{ "code": "STANDARD", "title": "Standard" }],
"shippingAddress": { "address1": "...", "city": "ENGLEWOOD", ... }
```

---

#### Case 2: Store Pickup / BOPIS

**Shopify signals:** `sourceName=web`, `retailLocation=null`, `shippingLines[0].code=STOREPICKUP`, line items have `_pickupstore` attribute

> [!IMPORTANT]
> The **BOPIS detection** happens at the **line item level**, not order level.  
> Key trigger: `lineItem.customAttributes` contains a property where key includes `"pickupstore"` (case-insensitive).  
> **Groovy lines 527–537:**
> ```groovy
> if (propName.contains("pickupstore") || propName.contains(storePickupProperty)) {
>     pickupStore = true
>     fromFacilityId = propValue  // e.g. "29"
>     shipmentMethodTypeIdForItem = "STOREPICKUP"
>     carrierPartyIdForItem = "_NA_"
> }
> ```

| `OrderItemShipGroup` Field | Value | Source in Shopify JSON |
|---------------------------|-------|------------------------|
| `shipmentMethodTypeId` | **`STOREPICKUP`** | Derived from `lineItem.customAttributes._pickupstore` |
| `carrierPartyId` | `_NA_` | Hard-coded for pickup |
| `facilityId` | Resolved from `_pickupstore` value | `lineItem.customAttributes._pickupstore` → Facility lookup |
| `orderFacilityId` | `null` | Web order, no retail location |
| `maySplit` | `Y` / `N` | Config |
| **shipTo** → `postalAddress` | Customer shipping address | `orderDetails.shippingAddress` |
| Item `statusId` | `ITEM_CREATED` | `unfulfilledQuantity > 0` |

```json
// Shopify (BOPIS line item):
"customAttributes": [
  { "key": "Delivery Method", "value": "Pick Up at Irvine Spectrum, 864 Spectrum Center Drive" },
  { "key": "_pickupstore",    "value": "29" },
  { "key": "Gift Wrap",       "value": "With Love" }
],
"shippingLines": [{ "code": "STOREPICKUP", "title": "In-Store Pick Up" }]
```

---

#### Case 3: Sand Sale

**Shopify signals:** `sourceName=pos`, `retailLocation={id}`, `shippingAddress` present, `displayFulfillmentStatus=UNFULFILLED`

> [!NOTE]
> Sand Sale = POS order where the item needs to be **shipped to the customer** (not picked up in-store).  
> The groovy skips using the `retailLocation` facility because `isCashSaleOrder=false` but `isMixedCartPOSOrder=true` (has shipping address).  
> If the order has the `SENDSALE` tag, `retailLocation` is explicitly ignored (line 248).

| `OrderItemShipGroup` Field | Value | Source in Shopify JSON |
|---------------------------|-------|------------------------|
| `shipmentMethodTypeId` | Mapped from `shippingLines[0].title` (e.g. `"Free Expedited"`) | `orderDetails.shippingLines[0]` |
| `carrierPartyId` | From ProductStore config | System config |
| `facilityId` | `defaultFacilityId` or `_NA_` | Not from retailLocation (overridden) |
| `orderFacilityId` | Retail location facility | `orderDetails.retailLocation.legacyResourceId` → `ShopifyShopLocation.facilityId` |
| **shipTo** | Customer's shipping address | `orderDetails.shippingAddress` |
| Item `statusId` | `ITEM_CREATED` | unfulfilled |

```json
// Shopify (Sand Sale):
"sourceName": "pos",
"retailLocation": { "legacyResourceId": "20523548731" },
"shippingAddress": { "address1": "10221 Kaimu Drive", "city": "Huntington Beach" },
"displayFulfillmentStatus": "UNFULFILLED",
"shippingLines": [{ "code": "Free Expedited", "title": "Free Expedited" }]
```

---

#### Case 4: POS Completed (Cash Sale / In-Store Walk-in)

**Shopify signals:** `sourceName=pos`, `retailLocation={id}`, `shippingAddress=null`, `displayFulfillmentStatus=FULFILLED`, `shippingLines=[]`

> [!IMPORTANT]
> The groovy detects this as `isCashSaleOrder=true` (line 224).  
> Ship method is **force-set to `POS_COMPLETED`** (line 442–444):
> ```groovy
> if (isCashSaleOrder) {
>     shipmentMethodTypeId = "POS_COMPLETED"
>     carrierPartyId = "_NA_"
> }
> ```

| `OrderItemShipGroup` Field | Value | Source |
|---------------------------|-------|--------|
| `shipmentMethodTypeId` | **`POS_COMPLETED`** | Forced — `isCashSaleOrder=true` |
| `carrierPartyId` | `_NA_` | Forced |
| `facilityId` | From `retailLocation` → `ShopifyShopLocation.facilityId` | `orderDetails.retailLocation.legacyResourceId` |
| `orderFacilityId` | Same as facilityId (retail location) | `retailLocation` |
| **shipTo** | Facility address (no customer ship address) | Fetched from `FacilityContactDetailByPurpose` |
| Item `statusId` | `ITEM_COMPLETED` | `displayFulfillmentStatus = FULFILLED` + `unfulfilledQuantity = 0` |
| `orderMap.statusId` | `ORDER_COMPLETED` | `displayFulfillmentStatus = FULFILLED` |

```json
// Shopify (POS Completed):
"sourceName": "pos",
"retailLocation": { "legacyResourceId": "87821025411" },
"shippingAddress": null,
"displayFulfillmentStatus": "FULFILLED",
"shippingLines": [],
"fulfillments": [{ "legacyResourceId": "5962827268227", "location": { "legacyResourceId": "87821025411" } }]
```

#### Transaction receipt confirms POS terminal:
```json
// receiptJson contains:
"card_source": "stripe_terminal",
"point_of_sale_device_id": "5581308035",
"location_id": "87821025411",
"read_method": "contactless_emv"   // physical card tap
```

---

#### Case 5: Mix Card (POS — partially fulfilled + partially unfulfilled)

**Shopify signals:** `sourceName=pos`, `retailLocation={id}`, `shippingAddress` present, `displayFulfillmentStatus≠FULFILLED`

> This is `isMixedCartPOSOrder=true` (line 227).  
> Items split into **two ship groups** based on `calculateFulfillmentSplit()`:
> - Fulfilled quantity → `shipmentMethodTypeId = "POS_COMPLETED"` (taken at store)
> - Unfulfilled quantity → `shipmentMethodTypeId = "STANDARD"` or `"STOREPICKUP"` (to be shipped/picked up)

| Split Part | `shipmentMethodTypeId` | `facilityId` | Item `statusId` |
|-----------|------------------------|-------------|----------------|
| **Fulfilled part** | `POS_COMPLETED` | Retail location facility | `ITEM_COMPLETED` |
| **Unfulfilled part** | `STANDARD` (or from item props) | `defaultFacilityId` | `ITEM_CREATED` |

Groovy lines 622–630:
```groovy
if (isMixedCartPOSOrder) {
    if ("FULFILLED".equalsIgnoreCase(splitType)) {
        effectiveShipmentMethod = "POS_COMPLETED"
        effectiveCarrierPartyId = "_NA_"
        effectiveFromFacilityId = facilityId  // retail location
    } else if (!"STOREPICKUP".equals(effectiveShipmentMethod)) {
        effectiveFromFacilityId = defaultFacilityId ?: fromFacilityId
    }
}
```

---

## C. Complete Shopify → OMS Field Mapping Summary

### Order-Level Fields

| Shopify JSON Path | OMS Entity / Field | Notes |
|------------------|--------------------|-------|
| `orderDetails.id` (GID) | `OrderIdentification[SHOPIFY_ORD_ID]` + `OrderHeader.externalId` | Resolved via `ShopifyHelper.resolveShopifyGid()` |
| `orderDetails.number` | `OrderIdentification[SHOPIFY_ORD_NO]` | e.g. `6774254` |
| `orderDetails.name` | `OrderIdentification[SHOPIFY_ORD_NAME]` + `OrderHeader.orderName` | e.g. `#GOR196774254` |
| `orderDetails.sourceName` | `OrderHeader.salesChannelEnumId` | via `SHOPIFY_ORDER_SOURCE` type mapping |
| `orderDetails.createdAt` | `OrderHeader.orderDate` | Parsed as Timestamp |
| `orderDetails.currencyCode` | `OrderHeader.currencyUomId` | |
| `orderDetails.currentTotalPriceSet.shopMoney.amount` | `OrderHeader.grandTotal` | |
| `orderDetails.displayFulfillmentStatus` | `OrderHeader.statusId` | FULFILLED→ORDER_COMPLETED |
| `orderDetails.retailLocation.legacyResourceId` | `OrderHeader.originFacilityId` | For POS orders only |
| `orderDetails.customerLocale` | `OrderHeader.localeString` | Base locale extracted |
| `orderDetails.customer.legacyResourceId` | `OrderRole[PLACING_CUSTOMER]` via `customerExternalId` | |
| `orderDetails.email` | `OrderContactMech[EMAIL_ADDRESS]` | |
| `orderDetails.phone` | `OrderContactMech[PHONE_NUMBER]` | |
| `orderDetails.tags[]` | `OrderHeader.internalCode` / `tags` | Used for skip logic, classification |
| `orderDetails.note` | `OrderNote.noteText` | HTML stripped |
| `orderDetails.customAttributes[]` | `OrderAttribute[attrName, attrValue]` | All key/value pairs |

### Item-Level Fields

| Shopify JSON Path | OMS Entity / Field | Notes |
|------------------|--------------------|-------|
| `lineItem.id` (GID) | `OrderItem.orderItemExternalId` | `resolveShopifyGid()` |
| `lineItem.variant.legacyResourceId` | Product lookup in `ShopifyShopProduct` | |
| `lineItem.variant.sku` | `OrderItem.sku` | Fallback product identifier |
| `lineItem.variant.barcode` | GoodIdentification `UPCA` lookup | Fallback |
| `lineItem.quantity` | `OrderItem.quantity` (base) | Split into fulfilled/unfulfilled |
| `lineItem.unfulfilledQuantity` | Used in `calculateFulfillmentSplit()` | |
| `lineItem.originalUnitPriceSet.shopMoney.amount` | `OrderItem.unitPrice` + `unitListPrice` | |
| `lineItem.taxable` | `OrderItem.taxCode` | |
| `lineItem.discountAllocations[]` | `OrderAdjustment[EXT_PROMO_ADJUSTMENT]` per item | Negated |
| `lineItem.taxLines[]` | `OrderAdjustment[SALES_TAX]` per item | |
| `lineItem.customAttributes[]` | `OrderItemAttribute[attrName, attrValue]` | All key/values |

### Ship Group Fields

| Shopify JSON Path / Derived | OMS `OrderItemShipGroup` Field | Notes |
|----------------------------|-------------------------------|-------|
| Derived from `sourceName` + `shippingAddress` | `shipmentMethodTypeId` | See routing table above |
| `retailLocation.legacyResourceId` → `ShopifyShopLocation` | `facilityId` | POS orders |
| `lineItem.customAttributes._pickupstore` | `facilityId` | BOPIS orders |
| `productStore.inventoryFacilityId` | `facilityId` | Web orders fallback |
| `shippingLines[0].title` | `shipmentMethodTypeId` | Web orders — mapped via `ShopifyShopCarrierShipment` |
| `shippingAddress.*` | `shipTo.postalAddress.*` | Customer delivery address |
| `shippingAddress.phone` / `order.phone` | `shipTo.phoneNumber.contactNumber` | |
| `order.email` | `shipTo.email.infoString` | |
| `productStore.allowSplit` | `maySplit` | `Y`/`N` |

### Order Adjustments (from `shippingLines` and `discountApplications`)

| Shopify JSON Path | OMS `OrderAdjustment.orderAdjustmentTypeId` | Notes |
|------------------|---------------------------------------------|-------|
| `shippingLines[].originalPriceSet.amount` | `SHIPPING_CHARGES` | Per shipping line |
| `shippingLines[].taxLines[].priceSet.amount` | `SHIPPING_SALES_TAX` | Per tax on shipping |
| `discountApplications[targetType=SHIPPING_LINE]` | `EXT_SHIP_ADJUSTMENT` | Shipping discount |
| `order.totalTipReceivedSet.shopMoney.amount` | `DONATION_ADJUSTMENT` | Tip |

---

## D. Quick Identification Decision Tree

```
orderDetails.sourceName == "pos"?
  ├─ YES:
  │   ├─ shippingAddress == null?
  │   │   └─ YES → POS COMPLETED (isCashSaleOrder=true)
  │   │              OMS: shipMethodTypeId = "POS_COMPLETED", statusId = "ORDER_COMPLETED"
  │   │
  │   └─ shippingAddress != null?
  │       ├─ displayFulfillmentStatus == "FULFILLED" → (shouldn't happen, but ORDER_COMPLETED)
  │       └─ status != FULFILLED → SAND SALE or MIX CARD (isMixedCartPOSOrder=true)
  │              - If all items unfulfilled → Sand Sale
  │              - If some items fulfilled, some not → Mix Card (2 ship groups)
  │
  └─ NO (sourceName == "web"):
      ├─ Any lineItem has customAttribute key containing "pickupstore"?
      │   └─ YES → BOPIS / STORE PICKUP
      │              OMS: shipMethodTypeId = "STOREPICKUP", facilityId from _pickupstore value
      │
      └─ NO → ONLINE ORDER (Standard)
                 OMS: shipMethodTypeId = "STANDARD", brokered from inventory facility
```

---

## E. Transactions — Payment Identifiers (POS vs Web)

### POS Order Transaction (`receiptJson` metadata):
```json
{
  "card_source": "stripe_terminal",      // ← POS terminal payment
  "point_of_sale_device_id": "5581308035",
  "location_id": "87821025411",
  "payment_device_name": "Tap to Pay on iPhone",
  "read_method": "contactless_emv"
}
```
→ `payment_method_types: ["card_present"]` (physical card)

### Web Order Transaction (`receiptJson` metadata):
```json
{
  "payments_extension": "true",
  "payments_extension_type": "card",
  "reconciliation_flow": "payments_api"
}
```
→ `payment_method_types: ["card"]` (online card)

### Sand Sale (Gift Card only):
```json
{
  "gateway": "gift_card",
  "receiptJson": { "gift_card_id": 523564253315, "gift_card_last_characters": "mqpb" }
}
```
→ Two `gift_card` transactions (partial payments from two gift cards)
