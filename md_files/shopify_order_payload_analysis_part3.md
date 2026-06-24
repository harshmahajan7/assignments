# `prepareTransformedShopifyOrderPayload.groovy` — Deep Dive (Part 3)
## Scope: Lines 425–1030 | Ship Groups, Line Items, Product Resolution, Adjustments

---

## 14. Pre-Selected Facility Settings (Lines 433–462)

These settings enable **SendSale** and **BOPIS** pre-assignment of items to facilities.

```groovy
// The tag that triggers pre-selected facility logic (e.g. "SENDSALE")
def preSelectedFacTag = ec.entity.find("ProductStoreSetting")
        .condition("settingTypeEnumId", "PRE_SLCTD_FAC_TAG").one()?.settingValue

if (preSelectedFacTag && tags.any { it.equalsIgnoreCase(preSelectedFacTag) }) {
    pickupFacSetting  = ProductStoreSetting[ORD_ITM_PICKUP_FAC]  // e.g. "Pickup Facility"
    shipFacSetting    = ProductStoreSetting[ORD_ITM_SHIP_FAC]    // e.g. "Ship Facility"
    shipMethSetting   = ProductStoreSetting[ORD_ITM_SHIP_METH]   // e.g. "Shipping Method"
}
```

| Setting | `settingTypeEnumId` | Example Value | Meaning |
|---|---|---|---|
| Pre-selected tag | `PRE_SLCTD_FAC_TAG` | `SENDSALE` | Which order tag activates per-item facility |
| Pickup facility prop | `ORD_ITM_PICKUP_FAC` | `Pickup Facility` | Item property name holding the pickup store ID |
| Ship facility prop | `ORD_ITM_SHIP_FAC` | `Ship From Facility` | Item property name holding the ship-from store ID |
| Ship method prop | `ORD_ITM_SHIP_METH` | `Shipping Method` | Item property name holding the ship method |

Also loaded:
```groovy
def storePickupProperty = SystemProperty["storepickup.item.property.name"]
// e.g. "pickupStore" — the item property key used for BOPIS
```

---

## 15. Line Item Loop — Per-Item Facility Resolution (Lines 466–624)

```groovy
lineItemsRaw.each { lineItem ->
    def properties = normalizeProperties(lineItem.customAttributes)
    boolean pickupStore = false
    String fromFacilityId = facilityId          // starts with order-level facility
    String shipmentMethodTypeIdForItem = shipmentMethodTypeId
    String carrierPartyIdForItem = carrierPartyId
    boolean hasPreSelectedFacility = false
```

### 15.1 Branch A — SendSale (Pre-Selected Facility Tag matches)

```groovy
if (properties && preSelectedFacTag && tags.any { it.equalsIgnoreCase(preSelectedFacTag) }) {

    // PICKUP property on item → BOPIS within SendSale
    def pickupProp = properties.find { p -> pickupNames.any { it.equalsIgnoreCase(p.key) } }
    if (pickupProp?.value) {
        fromFacilityId = pickupProp.value          // facility ID from item property
        hasPreSelectedFacility = true
        shipmentMethodTypeIdForItem = "STOREPICKUP"
        carrierPartyIdForItem = "_NA_"
    }

    // SHIP property on item → ship from a specific store
    def shipProp = properties.find { p -> shipNames.any { it.equalsIgnoreCase(p.key) } }
    if (shipProp?.value) {
        fromFacilityId = shipProp.value
        hasPreSelectedFacility = true
    }

    // SHIP METHOD property on item → override carrier/method
    def shipMethProp = properties.find { p -> shipMethNames.any { it.equalsIgnoreCase(p.key) } }
    if (shipMethProp?.value) {
        def match = ShopifyShopCarrierShipment.find { it.shopifyShippingMethod equalsIgnoreCase shipMethProp.value }
        if (match) shipmentMethodTypeIdForItem = match.shipmentMethodTypeId
    }
}
```

**SendSale Example Item Properties (Shopify `customAttributes`):**
```json
"customAttributes": [
  { "key": "Ship From Facility", "value": "STORE_NYC_001" },
  { "key": "Shipping Method",    "value": "Economy Shipping" }
]
```

---

### 15.2 Branch B — BOPIS (pickupStore property on item)

```groovy
} else if (properties) {
    properties.each { prop ->
        def propName = prop.key?.toLowerCase()
        if (propName.contains("pickupstore") ||
            (storePickupProperty && propName.contains(storePickupProperty.toLowerCase()))) {
            pickupStore = true
            fromFacilityId = prop.value ?: fromFacilityId   // store ID from item property
            shipmentMethodTypeIdForItem = "STOREPICKUP"
            carrierPartyIdForItem = "_NA_"
        }
    }
}
```

**BOPIS Example Item Properties:**
```json
"customAttributes": [
  { "key": "pickupStore", "value": "STORE_LA_001" }
]
```

Result: `fromFacilityId = "STORE_LA_001"`, `shipmentMethodTypeId = "STOREPICKUP"`

---

### 15.3 Branch C — External Fulfillment Service Allocation (Lines 538–547)

```groovy
if (!pickupStore) {
    if (!"Y".equalsIgnoreCase(productStore?.reserveInventory)) {
        def externalFulfillmentAllocations = ShopifyShopTypeMapping
                .where(mappedTypeId == "SHOP_FULL_SRVC_ALLOC")
        def fulfillmentService = lineItem.fulfillmentService
        if (fulfillmentService && externalFulfillmentAllocations) {
            def allocation = externalFulfillmentAllocations.find {
                it.mappedKey equalsIgnoreCase fulfillmentService
            }
            if (allocation?.mappedValue) fromFacilityId = allocation.mappedValue
        }
    }
}
```

Maps Shopify's `fulfillmentService` (e.g. `"amazon"`, `"shipbob"`) → OMS facility via `ShopifyShopTypeMapping[SHOP_FULL_SRVC_ALLOC]`.

---

## 16. Fulfillment Split → Two Ship Groups per Item (Lines 550–624)

```groovy
def fulfillmentSplit = calculateFulfillmentSplit(lineItem)
def splitItems = []

// Group 1: Already fulfilled portion (ITEM_COMPLETED)
if (fulfillmentSplit.fulfilledQty > 0) {
    splitItems.add([lineItem: lineItem, split: [
        splitQty:  fulfillmentSplit.fulfilledQty,
        splitRatio: fulfilledQty / originalQty,
        statusId:  "ITEM_COMPLETED",
        splitType: "FULFILLED"
    ]])
}

// Group 2: Remaining unfulfilled portion (ITEM_CREATED)
if (fulfillmentSplit.remainingQty > 0) {
    splitItems.add([lineItem: lineItem, split: [
        splitQty:  fulfillmentSplit.remainingQty,
        splitRatio: remainingQty / originalQty,
        statusId:  "ITEM_CREATED",
        splitType: "UNFULFILLED"
    ]])
}
```

**Example — Partially Fulfilled Web Order:**
- `quantity = 3`, `unfulfilledQuantity = 1`
- `fulfilledQty = 2`, `remainingQty = 1`
- → Ship Group 1: qty=2, status=`ITEM_COMPLETED`
- → Ship Group 2: qty=1, status=`ITEM_CREATED`

---

## 17. Ship Group Bucketing (Lines 597–624)

```groovy
splitItems.each { splitItem ->
    // POS Mixed Cart override
    if (isMixedCartPOSOrder) {
        if ("FULFILLED".equalsIgnoreCase(splitType)) {
            effectiveShipmentMethod = "POS_COMPLETED"
            effectiveCarrierPartyId = "_NA_"
            effectiveFromFacilityId = facilityId      // use resolved POS store
        }
    }

    // Normalize facility (ID or name → canonical ID)
    String bucketFacilityId = resolveFacilityId(effectiveFromFacilityId) ?: effectiveFromFacilityId

    // Bucket key: facility | method | carrier | splitType
    String shipGroupKey = "${bucketFacilityId}|${effectiveShipmentMethod}|${effectiveCarrierPartyId}|${splitType}"
    shipGroupBuckets[shipGroupKey] = shipGroupBuckets[shipGroupKey] ?: []
    shipGroupBuckets[shipGroupKey].add(splitItem)
}
```

**Ship Group Keys by Order Type:**

| Order Type | Example Key |
|---|---|
| Web/Standard | `_NA_\|STANDARD\|_NA_\|UNFULFILLED` |
| BOPIS | `STORE_LA_001\|STOREPICKUP\|_NA_\|UNFULFILLED` |
| SendSale (ship) | `STORE_NYC_001\|ECONOMY\|UPS\|UNFULFILLED` |
| POS Cash Sale | `STORE_POS\|POS_COMPLETED\|_NA_\|FULFILLED` |
| POS Mixed (fulfilled part) | `STORE_POS\|POS_COMPLETED\|_NA_\|FULFILLED` |
| POS Mixed (ship part) | `_NA_\|STANDARD\|_NA_\|UNFULFILLED` |

---

## 18. Product Resolution per Line Item (Lines 794–860)

```groovy
String variantId = item.variant?.legacyResourceId    // Shopify variant numeric ID

// Step 1: Try ShopifyShopProduct lookup
def shopifyShopProduct = ec.entity.find("co.hotwax.shopify.ShopifyShopProduct")
        .condition("shopId", shopId)
        .condition("shopifyProductId", variantId)
        .useCache(true).one()
if (shopifyShopProduct) productId = shopifyShopProduct.productId

// Step 2: Gift card special case
if (!variantId && item.isGiftCard) {
    def giftCardProduct = ShopifyShopTypeMapping
            .where(mappedTypeId == "SHOPIFY_PRODUCT_TYPE", mappedKey == "CUSTOM_GIFT_CARD").one()
    productId = giftCardProduct?.mappedValue
    isDigitalGoodLineItem = true
}

// Step 3: Fallback by SKU or Barcode (GoodIdentification)
if (!productId && productIdentifier) {
    def goodId = ec.entity.find("org.apache.ofbiz.product.product.GoodIdentification")
            .condition("goodIdentificationTypeId", goodIdentificationTypeId)  // "SKU" or "UPCA"
            .condition("idValue", productIdentifier)
            .useCache(true).one()
    productId = goodId?.productId
}

// Step 4: Auto-create placeholder product
if (!productId && internalName) {
    def out = ec.service.sync().name("create#org.apache.ofbiz.product.product.Product")
            .parameters([productTypeId: "FINISHED_GOOD", internalName: internalName, ...]).call()
    productId = out.productId

    // Register in ShopifyShopProduct
    ec.service.sync().name("create#co.hotwax.shopify.ShopifyShopProduct")
            .parameters([shopId: shopId, productId: productId, shopifyProductId: variantId]).call()
}
```

**OMS Entity: `co.hotwax.shopify.ShopifyShopProduct`**

| Column | Example | Notes |
|---|---|---|
| `shopId` | `HOTWAX_SHOP` | Shop context |
| `shopifyProductId` | `48528826695997` | Shopify variant legacy ID |
| `productId` | `10001` | OMS product ID |

**OMS Entity: `org.apache.ofbiz.product.product.GoodIdentification`**

| Column | Example | Notes |
|---|---|---|
| `goodIdentificationTypeId` | `SKU` or `UPCA` | Controlled by `productIdentifierEnumId` on ProductStore |
| `idValue` | `WSH01-28-Black` | The SKU or barcode value |
| `productId` | `10001` | OMS product ID |

**Product Identifier resolution controlled by `ProductStore.productIdentifierEnumId`:**

| `productIdentifierEnumId` | `goodIdentificationTypeId` | Field used |
|---|---|---|
| `SHOPIFY_PRODUCT_SKU` | `SKU` | `item.variant.sku` |
| `SHOPIFY_BARCODE` | `UPCA` | `item.variant.barcode` |

---

## 19. Item Map Construction (Lines 860–934)

```groovy
itemMap.productId    = productId
itemMap.itemExternalId = ShopifyHelper.resolveShopifyGid(item.id)   // numeric GID
itemMap.quantity     = splitQty ?: originalQty
itemMap.unitPrice    = mapMoneyAmount(item.originalUnitPriceSet ?: item.discountedUnitPriceSet ?: item.priceSet)
itemMap.unitListPrice = unitPrice
itemMap.sku          = item.sku
itemMap.taxCode      = item.taxable
itemMap.statusId     = isDigitalGoodLineItem ? "ITEM_COMPLETED"
                        : (splitInfo.statusId ?: (fulfilledQty == originalQty ? "ITEM_COMPLETED" : "ITEM_CREATED"))
```

**OMS Entity: `org.apache.ofbiz.order.order.OrderItem`**

| OMS Column | Source | Notes |
|---|---|---|
| `productId` | resolved | FK to Product |
| `externalId` | `item.id` GID | Links back to Shopify line item |
| `quantity` | `splitQty` | Portion of qty for this ship group |
| `unitPrice` | `originalUnitPriceSet` | Price per unit |
| `statusId` | computed | `ITEM_CREATED` or `ITEM_COMPLETED` |

---

## 20. Item Adjustments — Discounts & Taxes (Lines 883–933)

### Discount Allocations
```groovy
item.discountAllocations?.each { itemDiscount ->
    def discountedAmount = mapMoneyAmount(itemDiscount.allocatedAmountSet ?: itemDiscount.amount)
    itemAdjustments.add([
        type:     "EXT_PROMO_ADJUSTMENT",
        comments: "External Discount: ${discountCode}",
        amount:   discountedAmount.negate(),   // negative = discount
        setShipGroup: "N",
        attributes: [[attrName: "discount_code", attrValue: discountCode]]
    ])
}
```

### Tax Lines
```groovy
item.taxLines?.each { taxLine ->
    itemAdjustments.add([
        type:             "SALES_TAX",
        comments:         taxLine.title,
        amount:           mapMoneyAmount(taxLine.priceSet ?: taxLine.price),
        sourcePercentage: toBigDecimal(taxLine.rate),
        setShipGroup:     "N"
    ])
}
```

### Split Ratio Scaling
```groovy
// If this item is a partial split (e.g. 2 of 3 fulfilled), scale all adjustments proportionally
if (splitRatio.compareTo(BigDecimal.ONE) != 0) {
    itemAdjustments.each { adj ->
        adj.amount = adj.amount.multiply(splitRatio)
    }
}
```

**OMS Entity: `org.apache.ofbiz.order.order.OrderAdjustment`**

| `orderAdjustmentTypeId` | Meaning |
|---|---|
| `EXT_PROMO_ADJUSTMENT` | Line-item discount (negative amount) |
| `SALES_TAX` | Per-item tax |
| `SHIPPING_CHARGES` | Shipping fee (order-level) |
| `SHIPPING_SALES_TAX` | Tax on shipping |
| `EXT_SHIP_ADJUSTMENT` | Shipping discount |
| `DONATION_ADJUSTMENT` | Tip amount |

---

## 21. Item Attributes — Preorder / Backorder / Pickup (Lines 936–970)

```groovy
// Preorder check: tag on item OR product in preorder category
if (preorderTag && (propertyValues.any { it equalsIgnoreCase preorderTag }
        || isProductInPreorderCategory(prodCatalogId, productId))) {
    orderItemAttributes.add([attrName: "PreOrderItemProperty", attrValue: preorderTag])
}

// Backorder check
if (backorderTag && isProductInBackorderCategory(prodCatalogId, productId)) {
    orderItemAttributes.add([attrName: "BackOrderItemProperty", attrValue: backorderTag])
}

// Store pickup tag
if (storePickupProperty && propertyValues.any { it equalsIgnoreCase storePickupProperty }) {
    orderItemAttributes.add([attrName: "StorePickupItemProperty", attrValue: storePickupProperty])
}
```

**OMS Entities checked:**
- `org.apache.ofbiz.product.catalog.ProdCatalogCategory` — category type `PCCT_PREORDR`, `PCCT_BACKORDER`, `PCCT_PREORDR_NOT`
- `org.apache.ofbiz.product.category.ProductCategoryMember` — is this product in that category?

**OMS Entity: `org.apache.ofbiz.order.order.OrderItemAttribute`**

| `attrName` | Meaning |
|---|---|
| `PreOrderItemProperty` | Item is a pre-order |
| `BackOrderItemProperty` | Item is on backorder |
| `StorePickupItemProperty` | Item is BOPIS pickup |

---

## 22. Exchange Item Association (Lines 986–1003)

```groovy
def origProp = itemProperties.find { "original_line_item_id".equalsIgnoreCase(it.key) }
if (origProp?.value) {
    def assocItem = ec.entity.find("co.hotwax.order.OrderItemAndShipGroup")
            .condition("orderItemExternalId", origProp.value).useCache(true).one()
    if (assocItem) {
        itemMap.assocs = [[
            toOrderId:            assocItem.orderId,
            toOrderItemSeqId:     assocItem.orderItemSeqId,
            orderItemAssocTypeId: "EXCHANGE",
            quantity:             assocItem.quantity
        ]]
    }
}
```

Used for **exchange orders**: Shopify sends `original_line_item_id` as an item property pointing to the original order item.

**OMS Entity: `org.apache.ofbiz.order.order.OrderItemAssoc`**

| Column | Value |
|---|---|
| `orderItemAssocTypeId` | `EXCHANGE` |
| `toOrderId` | original OMS order ID |
| `toOrderItemSeqId` | original item seq |

---

## 23. Ship Group Assembly (Lines 710–1025)

```groovy
shipGroupBuckets.entrySet().each { entry ->
    def keyParts = entry.key.split("\\|")
    // facilityKey | shipMethod | carrier | splitType

    def shipGroup = [:]
    shipGroup.facilityId           = resolveFacilityId(facilityKey) ?: facilityKey
    shipGroup.orderFacilityId      = facilityId == "_NA_" ? null : facilityId
    shipGroup.carrierPartyId       = carrierForGroup ?: "_NA_"
    shipGroup.shipmentMethodTypeId = shipMethodForGroup ?: "STANDARD"
    shipGroup.maySplit             = allowSplit ? "Y" : "N"

    // SHIP_TO_STORE special case: facility is the destination, not source
    if ("SHIP_TO_STORE".equalsIgnoreCase(shipGroup.shipmentMethodTypeId)) {
        shipGroup.orderFacilityId = shipGroup.facilityId
        shipGroup.facilityId = "_NA_"
    }
```

### Ship-From Address
```groovy
// Loaded from FacilityContactDetailByPurpose
shipGroup.shipFrom = [
    postalAddress: [id: facilityAddress.contactMechId],
    phoneNumber:   [id: facilityPhone.contactMechId],
    email:         [id: facilityEmail.contactMechId]
]
```

**OMS Entity: `org.apache.ofbiz.product.facility.FacilityContactDetailByPurpose`**

| `contactMechPurposeTypeId` | Meaning |
|---|---|
| `PRIMARY_LOCATION` | Ship-from postal address |
| `PRIMARY_PHONE` | Ship-from phone |
| `PRIMARY_EMAIL` | Ship-from email |

### Ship-To Address
```groovy
def shipToAddress = mapAddress(shippingAddress)
if (!shipToAddress) shipToAddress = mapAddress(billingAddress)   // fallback to billing
shipGroup.shipTo = [
    postalAddress: shipToAddress,
    phoneNumber: [contactNumber: shippingAddress?.phone ?: order.phone],
    email: [infoString: order.email ?: customer.email]
]
```

For **POS Cash Sale** (no shipping address): falls back to facility's own address as ship-to with `additionalPurpose: "PICKUP_LOCATION"`.

**OMS Entity: `org.apache.ofbiz.order.order.OrderItemShipGroup`**

| Column | Notes |
|---|---|
| `facilityId` | Ship-from facility (or `_NA_`) |
| `orderFacilityId` | Requested facility (BOPIS, Ship-to-store) |
| `shipmentMethodTypeId` | e.g. `STANDARD`, `STOREPICKUP`, `POS_COMPLETED` |
| `carrierPartyId` | e.g. `UPS`, `_NA_` |
| `maySplit` | `Y`/`N` from ProductStore.allowSplit |
| `isGift` | `Y`/`N` from first item's isGift flag |
