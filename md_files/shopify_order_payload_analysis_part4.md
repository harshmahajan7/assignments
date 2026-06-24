# `prepareTransformedShopifyOrderPayload.groovy` — Deep Dive (Part 4)
## Scope: Lines 1029–1155 | Order Adjustments → Final Output + Full Order-Type Flows

---

## 24. Order-Level Adjustments (Lines 1029–1098)

### 24.1 Shipping Discounts (Lines 1033–1065)
```groovy
discountApplications.each { orderDiscount ->
    if (orderDiscount.targetType?.equalsIgnoreCase("SHIPPING_LINE")) {
        def discountAmt = BigDecimal.ZERO
        // Sum discount allocations across all shipping lines matching this discount
        shippingLines?.each { shippingLine ->
            shippingLine.discountAllocations?.each { alloc ->
                if (alloc.discountApplication?.index == orderDiscount.index) {
                    discountAmt += mapMoneyAmount(alloc.allocatedAmountSet ?: alloc.amount)
                }
            }
        }
        if (discountAmt > 0) {
            orderAdjustments.add([
                type:   "EXT_SHIP_ADJUSTMENT",
                amount: discountAmt.negate(),
                adjustmentAttributes: [[attrName: "discount_code", attrValue: discountCode]]
            ])
        }
    }
}
```

### 24.2 Tip (Lines 1068–1072)
```groovy
def tipAmount = toBigDecimal(order.totalTipReceivedSet?.shopMoney?.amount ?: BigDecimal.ZERO)
if (tipAmount > 0) {
    orderAdjustments.add([type: "DONATION_ADJUSTMENT", comments: "Tip", amount: tipAmount])
}
```
- Present mainly on **POS orders** where customers add a tip

### 24.3 Shipping Charges + Shipping Tax (Lines 1074–1098)
```groovy
shippingLines.each { shippingLine ->
    def price = mapMoneyAmount(shippingLine.originalPriceSet ?: shippingLine.priceSet ...)
    if (price > 0) {
        orderAdjustments.add([type: "SHIPPING_CHARGES", comments: shippingLine.title, amount: price])
    }
    shippingLine.taxLines?.each { taxLine ->
        orderAdjustments.add([
            type: "SHIPPING_SALES_TAX",
            sourcePercentage: toBigDecimal(taxLine.rate),
            amount: mapMoneyAmount(taxLine.priceSet)
        ])
    }
}
```

**All Adjustment Types → `org.apache.ofbiz.order.order.OrderAdjustment`**

| `orderAdjustmentTypeId` | Amount | Typical Order Types |
|---|---|---|
| `EXT_PROMO_ADJUSTMENT` | Negative (discount) | All |
| `SALES_TAX` | Positive | All |
| `SHIPPING_CHARGES` | Positive | Web, SendSale |
| `SHIPPING_SALES_TAX` | Positive | Web, SendSale |
| `EXT_SHIP_ADJUSTMENT` | Negative (shipping discount) | All |
| `DONATION_ADJUSTMENT` | Positive | POS |

---

## 25. Customer Classification (Lines 1104–1119)

```groovy
def customerClassMappings = ec.entity.find("co.hotwax.shopify.ShopifyShopTypeMapping")
        .condition("shopId", shopId)
        .condition("mappedTypeId", "SHOP_ORD_CUST_CLASS")
        .useCache(true).list()

def match = customerClassMappings.find { mapping ->
    tags.any { t -> t.equalsIgnoreCase(mapping.mappedKey) }
}
context.customerClassificationId = match?.mappedValue
```

Example: Tag `"VIP"` → `mappedValue = "VIP_CUSTOMER"` → stored in `context.customerClassificationId` for the calling service to apply.

---

## 26. Order Status URL as Content (Lines 1121–1153)

```groovy
def orderStatusUrl = order.statusPageUrl  // e.g. "https://hotwax.myshopify.com/.../orders/..."
if (orderStatusUrl) {
    // 1. Create DataResource (metadata)
    def dataResourceOut = ec.service.sync().name("create#org.apache.ofbiz.content.data.DataResource")
            .parameters([dataResourceTypeId: "ELECTRONIC_TEXT", mimeTypeId: "text/plain"]).call()

    // 2. Store URL text
    ec.service.sync().name("create#org.apache.ofbiz.content.data.ElectronicText")
            .parameters([dataResourceId: dataResourceOut.dataResourceId, textData: orderStatusUrl]).call()

    // 3. Create Content record
    def contentOut = ec.service.sync().name("create#org.apache.ofbiz.content.content.Content")
            .parameters([contentTypeId: "DOCUMENT", dataResourceId: ..., contentName: "Order Status URL"]).call()

    // 4. Associate to order
    orderMap.contents = [[contentId: contentOut.contentId, orderContentTypeId: "ORDER_STATUS_URL"]]
}
```

**OMS Entities created:**
- `org.apache.ofbiz.content.data.DataResource` — metadata for the URL
- `org.apache.ofbiz.content.data.ElectronicText` — stores the actual URL string
- `org.apache.ofbiz.content.content.Content` — content record
- `org.apache.ofbiz.order.order.OrderContent` — links content to order via `ORDER_STATUS_URL`

---

## 27. Final Return Value (Line 1154)

```groovy
return [order: orderMap, skipReason: skipReason]
```

| Key | Value | Notes |
|---|---|---|
| `order` | Complete `orderMap` | Full OMS order payload |
| `skipReason` | String or null | Non-null → calling service skips creation |

`orderMap` structure:
```
orderMap {
  externalId, orderName, channel, productStoreId,
  currencyCode, grandTotal, orderDate, statusId,
  originFacilityId, autoApprove, localeString,
  customerId, customerExternalId, firstName, lastName,
  customerEmail, customerPhone, orderContacts,
  tags, attributes, note, identifications,
  billTo, contents,
  adjustments: [ SHIPPING_CHARGES, SHIPPING_SALES_TAX, EXT_SHIP_ADJUSTMENT, DONATION_ADJUSTMENT ],
  shipGroups: [
    {
      facilityId, orderFacilityId, carrierPartyId,
      shipmentMethodTypeId, maySplit, isGift,
      shipFrom: { postalAddress, phoneNumber, email },
      shipTo:   { postalAddress, phoneNumber, email },
      items: [
        {
          productId, itemExternalId, quantity, unitPrice,
          statusId, sku, taxCode, isGift,
          adjustments: [ EXT_PROMO_ADJUSTMENT, SALES_TAX ],
          attributes: [ PreOrderItemProperty, ... ],
          assocs: [ { EXCHANGE link } ]
        }
      ]
    }
  ]
}
```

---

## 28. Complete Flow per Order Type

---

### 28.1 Web / Standard Order

**Shopify signals:** `sourceName = "web"`, `shippingAddress` present, no special tags, no `retailLocation`

```
order.sourceName = "web"
  → getTypeMapping(SHOPIFY_ORDER_SOURCE, "web") = "WEB_SALES_CHANNEL"
  → channelId = "WEB_SALES_CHANNEL"

isCashSaleOrder = false (has shipping address)
isMixedCartPOSOrder = false (not POS channel)

locationId = null (no retailLocation)
facilityId = productStore.inventoryFacilityId (if reserveInventory=Y) else "_NA_"

shipmentMethodTypeId = resolved from shippingLines[0].title
  → ShopifyShopCarrierShipment lookup OR ProductStoreShipmentMethView

Each line item:
  → no customAttributes with pickupStore
  → fromFacilityId = facilityId (warehouse default)
  → shipMethod = "STANDARD" or resolved

Fulfillment split:
  → UNFULFILLED items: status = ITEM_CREATED → one ship group
  → PARTIALLY_FULFILLED: two ship groups (ITEM_COMPLETED + ITEM_CREATED)

Ship group: { facilityId: "_NA_" or warehouse, method: "STANDARD", shipTo: shippingAddress }
```

**Key DB lookups:**
1. `ShopifyShopTypeMapping[SHOPIFY_ORDER_SOURCE, "web"]` → `WEB_SALES_CHANNEL`
2. `ProductStore` → `allowSplit`, `reserveInventory`, `inventoryFacilityId`
3. `ShopifyShopCarrierShipment` → shipping method
4. `ShopifyShopProduct` → productId per line item
5. `GoodIdentification` fallback → productId by SKU/barcode

---

### 28.2 BOPIS Order (Buy Online, Pick Up In Store)

**Shopify signals:** `sourceName = "web"`, item has `customAttributes: [{key: "pickupStore", value: "STORE_LA_001"}]`

```
order.sourceName = "web"
  → channelId = "WEB_SALES_CHANNEL"

isCashSaleOrder = false
isMixedCartPOSOrder = false

facilityId = "_NA_" (no retailLocation, no defaultFacilityId typically)

Line item loop:
  → properties = [{ key: "pickupStore", value: "STORE_LA_001" }]
  → propName.contains("pickupstore") = TRUE
  → pickupStore = true
  → fromFacilityId = "STORE_LA_001"
  → shipmentMethodTypeIdForItem = "STOREPICKUP"
  → carrierPartyIdForItem = "_NA_"

Bucket key: "STORE_LA_001|STOREPICKUP|_NA_|UNFULFILLED"

Ship group:
  facilityId = "STORE_LA_001"
  shipmentMethodTypeId = "STOREPICKUP"
  shipTo = shippingAddress (customer address) OR facility address
  items = [{ productId, quantity, status: ITEM_CREATED }]
```

**Key DB lookups:**
1. `SystemProperty["storepickup.item.property.name"]` → `"pickupStore"` (property key to detect)
2. `Facility` → validate `STORE_LA_001` exists
3. `FacilityContactDetailByPurpose[PRIMARY_LOCATION]` → ship-from address on ship group

---

### 28.3 SendSale Order

**Shopify signals:** `tags = ["SENDSALE"]`, `sourceName = "web"` or `"pos"`, `shippingAddress` present, item properties specify source facility

```
tags = ["SENDSALE"]
  → skip tag check: "SENDSALE" not in skip list → proceed

order.retailLocation present BUT:
  → tags.any { "SENDSALE".equalsIgnoreCase(it) } = TRUE
  → locationId = null  ← retailLocation is IGNORED for SendSale
  → facilityId = defaultFacilityId ?: "_NA_"

ProductStoreSetting[PRE_SLCTD_FAC_TAG] = "SENDSALE"
  → tags match → load ORD_ITM_PICKUP_FAC, ORD_ITM_SHIP_FAC, ORD_ITM_SHIP_METH settings

Line item loop (properties on item):
  { key: "Ship From Facility", value: "STORE_NYC_001" }
  { key: "Shipping Method",    value: "Economy Shipping" }

  → shipFacSetting matches "Ship From Facility"
  → fromFacilityId = "STORE_NYC_001"
  → hasPreSelectedFacility = true

  → shipMethSetting matches "Shipping Method"
  → ShopifyShopCarrierShipment lookup "Economy Shipping"
  → shipmentMethodTypeIdForItem = "ECONOMY"

Bucket key: "STORE_NYC_001|ECONOMY|UPS|UNFULFILLED"

Ship group:
  facilityId = "STORE_NYC_001"
  shipmentMethodTypeId = "ECONOMY"
  carrierPartyId = "UPS"
  shipTo = shippingAddress (customer's home address)
```

**Key DB lookups:**
1. `ProductStoreSetting[PRE_SLCTD_FAC_TAG]` → `"SENDSALE"` (the activating tag)
2. `ProductStoreSetting[ORD_ITM_SHIP_FAC]` → `"Ship From Facility"` (item property key)
3. `ProductStoreSetting[ORD_ITM_SHIP_METH]` → `"Shipping Method"` (item property key)
4. `ShopifyShopCarrierShipment` → resolve ship method from title
5. `Facility` → validate STORE_NYC_001

---

### 28.4 POS Order (Cash Sale)

**Shopify signals:** `sourceName = "pos"`, **no `shippingAddress`**, `retailLocation` present, `displayFulfillmentStatus = "FULFILLED"`

```
order.sourceName = "pos"
  → getTypeMapping(SHOPIFY_ORDER_SOURCE, "pos") = "POS_SALES_CHANNEL"
  → channelId = "POS_SALES_CHANNEL"

shippingAddress = {}  → isShippingAddressEmpty = TRUE
isCashSaleOrder = TRUE  (POS_SALES_CHANNEL + no shippingAddress)

locationId = order.retailLocation.legacyResourceId  (e.g. "65432198")
  → tags do NOT contain "SENDSALE" → locationId is SET

facilityId = resolveShopifyLocationFacility("65432198")
  → ShopifyShopLocation lookup → "STORE_CHICAGO_001"

shipmentMethodTypeId = "POS_COMPLETED"  (hardcoded for cash sale)
carrierPartyId = "_NA_"

Line item:
  displayFulfillmentStatus = "FULFILLED"
  → fulfilledQty = originalQty, remainingQty = 0
  → only FULFILLED split item created
  → statusId = "ITEM_COMPLETED"

Bucket key: "STORE_CHICAGO_001|POS_COMPLETED|_NA_|FULFILLED"

Ship group:
  facilityId = "STORE_CHICAGO_001"
  shipmentMethodTypeId = "STOREPICKUP" or "POS_COMPLETED"
  shipTo = null → falls back to facility's own address
            { additionalPurpose: "PICKUP_LOCATION" }

orderMap.statusId = "ORDER_COMPLETED" (all items ITEM_COMPLETED)

Tip:
  → order.totalTipReceivedSet → DONATION_ADJUSTMENT adjustment
```

**Key DB lookups:**
1. `ShopifyShopTypeMapping[SHOPIFY_ORDER_SOURCE, "pos"]` → `POS_SALES_CHANNEL`
2. `ShopifyShopLocation[shopId, "65432198"]` → `facilityId = "STORE_CHICAGO_001"`
3. `FacilityContactDetailByPurpose[PRIMARY_LOCATION]` → used as ship-to when no shipping address

---

## 29. Complete Entity Map Summary

| OMS Entity | Used For |
|---|---|
| `moqui.basic.Geo` | Country geo ID from alpha-2/3 |
| `moqui.basic.GeoAssocAndToDetail` | State/province geo ID |
| `moqui.basic.SystemProperty` | System-level config (skip tags, pickup property) |
| `co.hotwax.shopify.ShopifyShopTypeMapping` | Channel, tags, fulfillment allocation, gift card, customer class |
| `co.hotwax.shopify.ShopifyShopLocation` | Shopify location ID → OMS facility ID |
| `co.hotwax.shopify.ShopifyShopCarrierShipment` | Shopify shipping title → OMS method + carrier |
| `co.hotwax.shopify.ShopifyShopProduct` | Shopify variant ID → OMS product ID |
| `org.apache.ofbiz.product.store.ProductStore` | allowSplit, reserveInventory, autoApprove, etc. |
| `org.apache.ofbiz.product.store.ProductStoreSetting` | SAVE_BILL_TO_INF, DEFAULT_CARRIER, PRE_SLCTD_FAC_TAG, etc. |
| `org.apache.ofbiz.product.store.ProductStoreCatalog` | Which catalog belongs to the store |
| `co.hotwax.product.store.ProductStoreShipmentMethView` | Fallback shipping method lookup |
| `org.apache.ofbiz.product.facility.Facility` | Facility ID/name lookup |
| `org.apache.ofbiz.product.facility.FacilityContactDetailByPurpose` | Ship-from/to address on facility |
| `org.apache.ofbiz.product.product.GoodIdentification` | SKU / barcode → product ID fallback |
| `org.apache.ofbiz.product.catalog.ProdCatalogCategory` | Preorder / backorder category definitions |
| `org.apache.ofbiz.product.category.ProductCategoryMember` | Is this product in preorder/backorder category? |
| `co.hotwax.order.OrderItemAndShipGroup` | Exchange order: find original item |
| `org.apache.ofbiz.content.data.DataResource` | Order status URL metadata |
| `org.apache.ofbiz.content.data.ElectronicText` | Order status URL text |
| `org.apache.ofbiz.content.content.Content` | Content record |

**Services called (sync):**
| Service | When Called |
|---|---|
| `co.hotwax.util.UtilityServices.get#SystemProperty` | Skip tags, storePickupProperty |
| `create#org.apache.ofbiz.product.product.Product` | Auto-create placeholder product |
| `create#co.hotwax.shopify.ShopifyShopProduct` | Register new product in Shopify-OMS map |
| `co.hotwax.sob.order.ShopifyOrderHelperServices.explode#ShopifyOrderItems` | Explode qty>1 items |
| `create#DataResource`, `create#ElectronicText`, `create#Content` | Order status URL content |
