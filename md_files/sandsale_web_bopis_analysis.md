# Order Type Analysis — Sand Sale, Standard Web & BOPIS

---

## ORDER TYPE 1: Sand Sale (POS + Gift Card Split Tender + Ship to Home)

> [!IMPORTANT]
> Order: `#GOR196774254` | Shopify Order ID: `6831338979459` | Source: `pos`

A **Sand Sale** is a POS transaction where:
- The sale is completed **in-store by staff** (on POS terminal)
- Payment is made via **gift cards** (often split across 2 gift cards)
- The item is **shipped to the customer's home** (not handed over at counter)

---

### 1. POS Identifier (Sand Sale)

#### In Shopify

| Field | Value | Significance |
|---|---|---|
| `sourceName` | `"pos"` | **Primary POS identifier** |
| `retailLocation.id` | `gid://shopify/Location/20523548731` | Physical store where sale was processed |
| `retailLocation.legacyResourceId` | `20523548731` | Store location numeric ID |
| `billingAddress` | `null` | Card-present POS — no billing address captured |
| `shippingAddress` | Present (Huntington Beach, CA) | **Key differentiator from POS-completed** — item is SHIPPED |
| `shippingLines[0].title` | `"Free Expedited"` | Shipping method chosen at POS for home delivery |
| `shippingLines[0].code` | `"Free Expedited"` | Free shipping given on sand sale |
| `displayFulfillmentStatus` | `"UNFULFILLED"` | Not yet shipped — requires warehouse fulfillment |
| `fulfillments` | `[]` | No fulfillment yet (unlike POS-completed) |
| `transactions[].gateway` | `"gift_card"` | **Split gift card payment — NOT card_present** |

#### In OMS

| OMS Field / Entity | Value | Notes |
|---|---|---|
| `Order.salesChannelEnumId` | `POS_SALES_CHANNEL` | From `sourceName = "pos"` |
| `OrderAttribute[SOURCE_NAME]` | `pos` | Channel identifier |
| `OrderAttribute[RETAIL_LOCATION_ID]` | `20523548731` | Store where order was placed |
| `OrderItemShipGroup.shipmentMethodTypeId` | `SECOND_DAY` / `FREE_EXPEDITED` | Mapped from `"Free Expedited"` shipping line |
| `OrderItemShipGroup.facilityId` | Warehouse/DC | Ships from DC, NOT the store |
| `OrderItemShipGroup.contactMechId` | Customer's shipping address | Present (unlike POS-completed) |
| `OrderPaymentPreference[0]` | Gift Card 1 — $2,000.00 | `gift_card_id: 523564253315`, last chars: `mqpb` |
| `OrderPaymentPreference[1]` | Gift Card 2 — $1,970.59 | `gift_card_id: 523564286083`, last chars: `y9dw` |

---

### 2. Mix Card — Split Gift Card Payment

This is the actual "mix" in Sand Sale: **Two separate gift cards** split across the total:

| | Transaction 0 | Transaction 1 |
|---|---|---|
| `kind` | `SALE` | `SALE` |
| `gateway` | `gift_card` | `gift_card` |
| `status` | `SUCCESS` | `SUCCESS` |
| `amount` | `$2,000.00` | `$1,970.59` |
| `gift_card_id` | `523564253315` | `523564286083` |
| `gift_card_last_characters` | `mqpb` | `y9dw` |
| `paymentDetails` | `null` | `null` |
| `parentTransaction` | `null` | `null` |
| Total | **$3,970.59** ✅ | |

> [!NOTE]
> Gift card transactions have `paymentDetails: null` and no `receiptJson` with card/terminal details. The `gift_card_id` and `last_characters` are the only identifiers. Both are `SALE` kind (not AUTH+CAPTURE like card_present).

---

### 3. OMS Entity Mappings — Sand Sale

#### A. `OrderAttribute`

| `attrName` | `attrValue` | Source |
|---|---|---|
| `SOURCE_NAME` | `pos` | `order.sourceName` |
| `SHOPIFY_ORDER_NAME` | `#GOR196774254` | `order.name` |
| `SHOPIFY_ORDER_ID` | `6831338979459` | `order.legacyResourceId` |
| `RETAIL_LOCATION_ID` | `20523548731` | `order.retailLocation.legacyResourceId` |
| `SHOPIFY_CUSTOMER_ID` | `7165436690563` | `order.customer.legacyResourceId` |
| `CUSTOMER_LOCALE` | `en-US` | `order.customerLocale` |
| `PAYMENT_GATEWAY` | `gift_card` | `order.transactions[].gateway` |

#### B. `OrderItemAttribute`

| `attrName` | `attrValue` | Source |
|---|---|---|
| `SHOPIFY_LINE_ITEM_ID` | `15455370838147` | `lineItem.legacyResourceId` |
| `SHOPIFY_PRODUCT_VARIANT_ID` | `42751209373827` | `lineItem.variant.legacyResourceId` |
| `IS_GIFT_CARD` | `false` | `lineItem.isGiftCard` |
| `REQUIRES_SHIPPING` | `true` | `lineItem.requiresShipping` |
| `FULFILLMENT_SERVICE` | `Manual` | `lineItem.variant.fulfillmentService.serviceName` |

> [!NOTE]
> `lineItem.customAttributes = []` — no custom attributes on the line item.

#### C. `OrderItemShipGroup` (Sand Sale — Ship to Home)

| Field | Value | Source |
|---|---|---|
| `shipGroupSeqId` | `00001` | Auto-generated |
| `facilityId` | DC/Warehouse facility | Ships from DC (not store) |
| `shipmentMethodTypeId` | `FREE_EXPEDITED` / `SECOND_DAY` | From `shippingLines[0].title = "Free Expedited"` |
| `carrierPartyId` | Carrier (e.g., FedEx/UPS) | Not `_NA_` — real carrier for home delivery |
| `contactMechId` | Mapped from `shippingAddress` | Huntington Beach, CA 92646 |
| `telecomNumber` | `+17146252181` | `shippingAddress.phone` |

---

---

## ORDER TYPE 2: Standard Web Order (Online / Ship to Home)

> [!IMPORTANT]
> Order: `#GOR196774298` | Shopify Order ID: `6831381676163` | Source: `web`

---

### 1. Web Order Identifier

#### In Shopify

| Field | Value | Significance |
|---|---|---|
| `sourceName` | `"web"` | **Online order — NOT POS** |
| `retailLocation` | `null` | No physical store involved |
| `shippingAddress` | Present (Englewood, CO) | Home delivery |
| `billingAddress` | Present (Kearny, NJ) | Card billing address captured |
| `shippingLines[0].title` | `"Standard"` | Standard shipping ($8.00) |
| `shippingLines[0].code` | `"STANDARD"` | |
| `displayFulfillmentStatus` | `"UNFULFILLED"` | Pending fulfillment |
| `transactions[0].kind` | `SALE` | Direct capture (not auth+capture) |
| `transactions[0].gateway` | `shopify_payments` | Online Shopify Payments |
| `wallet.type` | `"apple_pay"` | **Paid via Apple Pay** |
| `payment_method_types` | `["card"]` | Online card (NOT card_present) |
| `order.note` | `"To the most beautiful Rose..."` | Gift order with note |
| `tags` | `fashion, firstorder, gifter, shipBooklet` | Marketing tags |

#### In OMS

| OMS Field / Entity | Value | Notes |
|---|---|---|
| `Order.salesChannelEnumId` | `WEB_SALES_CHANNEL` | From `sourceName = "web"` |
| `Order.orderTypeId` | `SALES_ORDER` | Standard |
| `Order.internalCode` | `#GOR196774298` | Order name |
| `OrderAttribute[SOURCE_NAME]` | `web` | |
| `OrderAttribute[IS_FIRST_ORDER]` | `true` | From tag `firstorder` |
| `OrderAttribute[IS_GIFTER]` | `true` | From tag `gifter` |
| `OrderItemShipGroup.shipmentMethodTypeId` | `STANDARD` | From `shippingLines[0].code` |
| `OrderItemShipGroup.contactMechId` | CO shipping address | Home delivery |
| `OrderPaymentPreference.paymentMethodTypeId` | `CREDIT_CARD` / `EXT_SHOP_APPLE_PAY` | Apple Pay (Mastercard) |
| `Order.orderNotes` | Gift note text | From `order.note` |

---

### 2. Payment — Apple Pay (Mastercard) — Web

Single SALE transaction, `capture_method: automatic`:

| Field | Value |
|---|---|
| `kind` | `SALE` |
| `gateway` | `shopify_payments` |
| `amount` | `$76.94` |
| `payment_method_types` | `["card"]` (online, NOT card_present) |
| `wallet.type` | `apple_pay` |
| `wallet.dynamic_last4` | `9245` (tokenized card number) |
| `brand` | `mastercard` |
| `last4` (actual card) | `0000` |
| `issuer` | `CAPITAL ONE, NATIONAL ASSOCIAT` |
| `funding` | `credit` |
| `capture_method` | `automatic` (instant capture — no separate CAPTURE transaction) |
| `risk_level` | `normal` |
| `payments_extension_type` | `card` |

> [!NOTE]
> Unlike POS (card_present + manual capture), web payments use `payment_method_types: ["card"]` with `capture_method: automatic`. Apple Pay wraps the underlying card, so `last4` reflects the actual card (`0000`) while `dynamic_last4` (`9245`) reflects the tokenized device PAN.

---

### 3. OMS Entity Mappings — Standard Web Order

#### A. `OrderAttribute`

| `attrName` | `attrValue` | Source |
|---|---|---|
| `SOURCE_NAME` | `web` | `order.sourceName` |
| `SHOPIFY_ORDER_NAME` | `#GOR196774298` | `order.name` |
| `SHOPIFY_ORDER_ID` | `6831381676163` | `order.legacyResourceId` |
| `SHOPIFY_CUSTOMER_ID` | `8652927041667` | `order.customer.legacyResourceId` |
| `CUSTOMER_LOCALE` | `en-US` | `order.customerLocale` |
| `POLAR_ATTR` | `eyJ1c2VySW...` (base64) | `customAttributes[polar_attr]` — analytics |
| `LAYERS_SESSION_ID` | `48b412f6-78d3-...` | `customAttributes[_layers_session_id]` |
| `TOLSTOY_ANONYMOUS_ID` | `5c9346a2-8a6e-...` | `customAttributes[__tolstoyAnonymousId]` |
| `GIFT_WRAP_OPTION` | `Gift Wrap Items Together` | `order.customAttributes[Gift Wrap Option]` |
| `ORDER_NOTE` | `"To the most beautiful Rose..."` | `order.note` |
| `PAYMENT_GATEWAY` | `shopify_payments` | `transactions[0].gateway` |

#### B. `OrderItemAttribute`

| `attrName` | `attrValue` | Source |
|---|---|---|
| `SHOPIFY_LINE_ITEM_ID` | `15455428051075` | `lineItem.legacyResourceId` |
| `SHOPIFY_PRODUCT_VARIANT_ID` | `20823731044411` | `lineItem.variant.legacyResourceId` |
| `DELIVERY_METHOD` | `Ship to Me` | `lineItem.customAttributes[Delivery Method]` |
| `GIFT_WRAP` | `With Love` | `lineItem.customAttributes[Gift Wrap]` |
| `IS_GIFT_CARD` | `false` | `lineItem.isGiftCard` |
| `REQUIRES_SHIPPING` | `true` | `lineItem.requiresShipping` |

#### C. `OrderItemShipGroup` — Standard Web

| Field | Value | Source |
|---|---|---|
| `shipGroupSeqId` | `00001` | Auto-generated |
| `facilityId` | Warehouse/DC | Home delivery, ships from DC |
| `shipmentMethodTypeId` | `STANDARD` | From `shippingLines[0].code` |
| `carrierPartyId` | Carrier (FedEx/UPS) | Real carrier |
| `contactMechId` | Englewood, CO 80112 | From `shippingAddress` |
| `shipmentMethodPrice` | `$8.00` | `shippingLines[0].originalPriceSet` |

---

---

## ORDER TYPE 3: BOPIS / In-Store Pickup

> [!IMPORTANT]
> Order: `#GOR196774299` | Shopify Order ID: `6831393996931` | Source: `web` | Tag: `bopis`

---

### 1. BOPIS Identifier

#### In Shopify

| Field | Value | Significance |
|---|---|---|
| `sourceName` | `"web"` | Online order (NOT pos) |
| `retailLocation` | `null` | No retailLocation on BOPIS |
| `tags[0]` | `"bopis"` | **Primary BOPIS identifier in Shopify** |
| `shippingLines[0].code` | `"STOREPICKUP"` | **Key BOPIS signal** |
| `shippingLines[0].title` | `"In-Store Pick Up"` | Display name |
| `shippingLines[0].originalPriceSet` | `$0.00` | Free pickup |
| `lineItem.customAttributes[Delivery Method]` | `"Pick Up at Irvine Spectrum, 864 Spectrum Center Drive"` | **Store + address in custom attr** |
| `lineItem.customAttributes[_pickupstore]` | `"29"` | **Store facility ID in Shopify custom attr** |
| `displayFulfillmentStatus` | `"UNFULFILLED"` | Ready for store to pick & pack |
| `shippingAddress` | Present (Trabuco Canyon, CA) | Customer's home address (for records) |
| `billingAddress` | Same as shipping | Normal card billing |
| `payment_method_types` | `["card"]` | Online card payment |

#### In OMS

| OMS Field / Entity | Value | Notes |
|---|---|---|
| `Order.salesChannelEnumId` | `WEB_SALES_CHANNEL` | `sourceName = "web"` |
| `OrderAttribute[SOURCE_NAME]` | `web` | |
| `OrderAttribute[BOPIS_TAG]` | `bopis` | From `order.tags` |
| `OrderItemShipGroup.shipmentMethodTypeId` | `STOREPICKUP` | From `shippingLines[0].code` |
| `OrderItemShipGroup.facilityId` | Store facility mapped from `_pickupstore = 29` | **Fulfilling store, not DC** |
| `OrderItemShipGroup.contactMechId` | Store address | Pickup location |
| `OrderItemAttribute[_pickupstore]` | `29` | From `lineItem.customAttributes` |
| `OrderItemAttribute[DELIVERY_METHOD]` | `"Pick Up at Irvine Spectrum..."` | Pickup location text |

---

### 2. Payment — Visa (BOPIS — Online Card)

Single SALE transaction, `capture_method: automatic`:

| Field | Value |
|---|---|
| `kind` | `SALE` |
| `gateway` | `shopify_payments` |
| `amount` | `$202.58` |
| `payment_method_types` | `["card"]` |
| `brand` | `visa` |
| `last4` | `0284` |
| `issuer` | `CITIBANK, N.A.- COSTCO` |
| `funding` | `credit` |
| `wallet` | `null` (physical card, no wallet) |
| `network_token.used` | `true` |
| `address_line1_check` | `pass` |
| `address_postal_code_check` | `pass` |
| `cvc_check` | `pass` |
| `capture_method` | `automatic` |

---

### 3. OMS Entity Mappings — BOPIS

#### A. `OrderAttribute`

| `attrName` | `attrValue` | Source |
|---|---|---|
| `SOURCE_NAME` | `web` | `order.sourceName` |
| `SHOPIFY_ORDER_NAME` | `#GOR196774299` | `order.name` |
| `SHOPIFY_ORDER_ID` | `6831393996931` | `order.legacyResourceId` |
| `SHOPIFY_CUSTOMER_ID` | `8023636705411` | `order.customer.legacyResourceId` |
| `BOPIS_TAG` | `bopis` | `order.tags[0]` |
| `GIFT_WRAP_OPTION` | `Gift Wrap Items Separately` | `order.customAttributes[Gift Wrap Option]` |
| `TOLSTOY_ANONYMOUS_ID` | `6b1765f5-...` | `order.customAttributes[__tolstoyAnonymousId]` |
| `LAYERS_SESSION_ID` | `802e2e03-...` | `order.customAttributes[_layers_session_id]` |
| `POLAR_ATTR` | `eyJ1c2VySWQi...` (base64) | `order.customAttributes[polar_attr]` |
| `PAYMENT_GATEWAY` | `shopify_payments` | `transactions[0].gateway` |

#### B. `OrderItemAttribute` (3 Line Items)

| `attrName` | Item 0 (Necklace) | Item 1 (Charm) | Item 2 (Necklace) | Source |
|---|---|---|---|---|
| `SHOPIFY_LINE_ITEM_ID` | `15455443746947` | `15455443779715` | `15455443812483` | `lineItem.legacyResourceId` |
| `SHOPIFY_PRODUCT_VARIANT_ID` | `44449001242755` | `45545960407171` | `45165208797315` | `lineItem.variant.legacyResourceId` |
| `DELIVERY_METHOD` | `Pick Up at Irvine Spectrum...` | `Pick Up at Irvine Spectrum...` | `Pick Up at Irvine Spectrum...` | `customAttributes[Delivery Method]` |
| `_PICKUPSTORE` | `29` | `29` | `29` | `customAttributes[_pickupstore]` |
| `LAYERS_ATTRIBUTION` | `01KSKWYCM6PE8XRQ78Y9J3C1G7` | `01KSGEM5J778JAW8FJK2F8P7QV` | `01KSGE60JWR1BRR5XJJ1CPPZNA` | `customAttributes[_layers_attribution]` |
| `GIFT_WRAP` | `With Love` | `With Love` | `With Love` | `customAttributes[Gift Wrap]` |
| `IS_GIFT_CARD` | `false` | `false` | `false` | `lineItem.isGiftCard` |
| `REQUIRES_SHIPPING` | `true` | `true` | `true` | `lineItem.requiresShipping` |

#### C. `OrderItemShipGroup` — BOPIS (Single Ship Group — All 3 items to same store)

| Field | Value | Source |
|---|---|---|
| `shipGroupSeqId` | `00001` | Auto-generated |
| `facilityId` | Facility mapped from `_pickupstore = 29` | Store: Irvine Spectrum |
| `shipmentMethodTypeId` | `STOREPICKUP` | From `shippingLines[0].code = "STOREPICKUP"` |
| `carrierPartyId` | `_NA_` | No carrier — customer picks up |
| `shipmentMethodPrice` | `$0.00` | Free pickup |
| `contactMechId` | Store address (Irvine Spectrum) | Pickup point |

#### `OrderItemShipGroupAssoc` (All 3 items)

| `orderItemSeqId` | SKU | `quantity` |
|---|---|---|
| `00001` | `247-100-G` (Crew Interlocking Necklace) | 1 |
| `00002` | `258-104-G` (Forget Me Not Parker Charm) | 1 |
| `00003` | `253-107-G` (Parker Delicate Necklace) | 1 |

---

---

## Quick Comparison — All 4 Order Types

| Signal | POS-Completed | Sand Sale | Web-Standard | BOPIS |
|---|---|---|---|---|
| `sourceName` | `pos` | `pos` | `web` | `web` |
| `retailLocation` | ✅ Present | ✅ Present | ❌ null | ❌ null |
| `tags` | — | — | fashion, firstorder | **bopis**, firstorder |
| `shippingLines` | `[]` (none) | Free Expedited | STANDARD ($8) | STOREPICKUP ($0) |
| `shippingAddress` | `null` | ✅ Home address | ✅ Home address | ✅ Home address |
| `billingAddress` | `null` | `null` | ✅ Present | ✅ Present |
| `fulfillments` | ✅ Fulfilled | `[]` | `[]` | `[]` |
| `displayFulfillmentStatus` | `FULFILLED` | `UNFULFILLED` | `UNFULFILLED` | `UNFULFILLED` |
| Payment gateway | `shopify_payments` (card_present) | `gift_card` (x2) | `shopify_payments` (online card) | `shopify_payments` (online card) |
| Transaction kind | AUTH + CAPTURE | SALE + SALE | SALE | SALE |
| `capture_method` | `manual` | — | `automatic` | `automatic` |
| `payment_method_types` | `card_present` | N/A | `card` | `card` |
| `lineItem.customAttributes` | `[]` | `[]` | Delivery Method, Gift Wrap | Delivery Method, _pickupstore, Gift Wrap |
| OMS `salesChannelEnumId` | `POS_SALES_CHANNEL` | `POS_SALES_CHANNEL` | `WEB_SALES_CHANNEL` | `WEB_SALES_CHANNEL` |
| OMS `facilityId` (ship group) | Store (counter) | DC/Warehouse | DC/Warehouse | **Store** (`_pickupstore=29`) |
| OMS `shipmentMethodTypeId` | `POS_COMPLETED` | `FREE_EXPEDITED` | `STANDARD` | `STOREPICKUP` |

---

## Key Differentiators Summary

```
POS-Completed:  sourceName=pos + retailLocation + shippingLines=[] + FULFILLED (immediate)
Sand Sale:      sourceName=pos + retailLocation + shippingAddress + gift_card transactions + UNFULFILLED
Web-Standard:   sourceName=web + retailLocation=null + shippingLines[STANDARD] + online card/wallet
BOPIS:          sourceName=web + tags[bopis] + shippingLines[STOREPICKUP] + _pickupstore in lineItem.customAttributes
```
