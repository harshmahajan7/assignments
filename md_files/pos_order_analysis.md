# POS Order Analysis — Completed Case (Mix Card via Stripe Terminal)

> [!IMPORTANT]
> Order: `#GOR196774286` | Shopify Order ID: `6831365849219` | Source: `pos`

---

## 1. POS Order Identifiers

### A. In Shopify

| Field | Value | Significance |
|---|---|---|
| `sourceName` | `"pos"` | **Primary POS identifier** — set by Shopify POS app on order creation |
| `retailLocation.id` | `gid://shopify/Location/87821025411` | Links order to a physical store location |
| `retailLocation.legacyResourceId` | `87821025411` | Numeric location ID (use for REST API lookups) |
| `shippingAddress` | `null` | POS orders typically have no shipping address |
| `billingAddress` | `null` | Card-present transactions don't capture billing address |
| `shippingLines` | `[]` | No shipping lines — in-store pickup/immediate handoff |
| `transactions[].receiptJson` → `card_source` | `"stripe_terminal"` | Payment via physical/tap-to-pay terminal |
| `transactions[].receiptJson` → `read_method` | `"contactless_emv"` | Tap-to-pay (NFC) used |
| `transactions[].receiptJson` → `payment_method_types` | `["card_present"]` | Physical card-present transaction |
| `fulfillments[0].location.id` | `gid://shopify/Location/87821025411` | Fulfilled at the same store location |
| `displayFulfillmentStatus` | `"FULFILLED"` | POS orders are immediately fulfilled at the counter |

### B. In OMS (HotWax / OFBiz)

| OMS Field / Entity | Value / Source | How to Identify POS |
|---|---|---|
| `Order.salesChannelEnumId` | Set to `POS_SALES_CHANNEL` | Mapped from `sourceName = "pos"` |
| `Order.orderTypeId` | `SALES_ORDER` | Same as eComm, but channel differentiates it |
| `OrderAttribute` | Key: `SOURCE_NAME`, Value: `pos` | Stored verbatim from Shopify for traceability |
| `OrderAttribute` | Key: `SHOPIFY_SOURCE_NAME`, Value: `pos` | Connector-level attribute |
| `OrderFacility` / `facilityId` | Mapped from `retailLocation.legacyResourceId` (`87821025411`) | Identifies the physical store/facility |
| `OrderItemShipGroup.facilityId` | Same store facility ID | Pickup/counter-fulfillment at the store |
| `OrderItemShipGroup.shipmentMethodTypeId` | `STOREPICKUP` or `POS_COMPLETED` | No carrier; goods handed at counter |
| `OrderPaymentPreference.paymentMethodTypeId` | `EXT_SHOP_STRIPE_TERMINAL` or `CREDIT_CARD` | Card-present terminal payment |

---

## 2. Mix Card Payment — Stripe Terminal (Mastercard)

This order uses **two transactions** (Authorization + Capture), which is the standard Stripe Terminal flow:

### Transaction 0 — AUTHORIZATION
| Field | Value |
|---|---|
| `kind` | `AUTHORIZATION` |
| `status` | `SUCCESS` |
| `amount` | `$81.28` |
| `gateway` | `shopify_payments` |
| `paymentDetails.company` | `Mastercard` |
| `card_source` (receipt) | `stripe_terminal` |
| `payment_method_types` | `card_present` |
| `read_method` | `contactless_emv` (Tap to Pay) |
| `payment_device_name` | `Tap to Pay on iPhone` |
| `issuer` | `CITIBANK N.A.` |
| `last4` | `8970` |
| `capture_method` | `manual` (Stripe holds auth, Shopify captures) |

### Transaction 1 — CAPTURE
| Field | Value |
|---|---|
| `kind` | `CAPTURE` |
| `status` | `SUCCESS` |
| `amount` | `$81.28` |
| `parentTransaction.id` | `gid://shopify/OrderTransaction/7957069987971` |
| `captured` | `true` |
| `status` (Stripe) | `succeeded` |
| `amount_received` | `8128` (cents) |

> [!NOTE]
> **"Mix Card"** in POS context means the payment instrument is a physical card (card_present) processed through Stripe Terminal, as opposed to a Shopify online card or gift card. In a true "split tender" scenario, multiple payment methods (e.g., part gift card + part credit card) would appear as separate transaction entries.

---

## 3. OMS Entity Mappings from Shopify JSON

### A. `OrderAttribute` (Order-level custom attributes)

Maps from `customAttributes` (order-level) and key receipt metadata:

| `attrName` | `attrValue` | Source in Shopify JSON |
|---|---|---|
| `SOURCE_NAME` | `pos` | `order.sourceName` |
| `SHOPIFY_ORDER_NAME` | `#GOR196774286` | `order.name` |
| `SHOPIFY_ORDER_ID` | `6831365849219` | `order.legacyResourceId` |
| `RETAIL_LOCATION_ID` | `87821025411` | `order.retailLocation.legacyResourceId` |
| `SHOPIFY_CUSTOMER_ID` | `8652915146883` | `order.customer.legacyResourceId` |
| `CUSTOMER_LOCALE` | `en` | `order.customerLocale` |
| `PAYMENT_GATEWAY` | `shopify_payments` | `order.transactions[].gateway` |
| `CARD_SOURCE` | `stripe_terminal` | `receiptJson.metadata.card_source` |
| `PAYMENT_DEVICE_NAME` | `Tap to Pay on iPhone` | `receiptJson.metadata.payment_device_name` |
| `POINT_OF_SALE_DEVICE_ID` | `5581308035` | `receiptJson.metadata.point_of_sale_device_id` |
| `CHECKOUT_SESSION_ID` | `6537CBCA-1F74-4719-9D79-1036B3BD0AD1` | `receiptJson.metadata.checkout_session_identifier` |

---

### B. `OrderItemAttribute` (Line-item level attributes)

Maps from each `lineItem` in `order.lineItems[]` and `lineItem.customAttributes[]`:

| `attrName` | `attrValue` (Item 0: Scallop Necklace) | `attrValue` (Item 1: Seaside Tote) | Source |
|---|---|---|---|
| `SHOPIFY_LINE_ITEM_ID` | `15455405801603` | `15455405834371` | `lineItem.legacyResourceId` |
| `SHOPIFY_PRODUCT_VARIANT_ID` | `47143792574595` | `47188252393603` | `lineItem.variant.legacyResourceId` |
| `IS_GIFT_CARD` | `false` | `false` | `lineItem.isGiftCard` |
| `REQUIRES_SHIPPING` | `true` | `true` | `lineItem.requiresShipping` |
| `FULFILLMENT_SERVICE` | `Manual` | `Manual` | `lineItem.variant.fulfillmentService.serviceName` |

> [!NOTE]
> `lineItem.customAttributes` is `[]` for both items in this order — no additional item-level custom attributes.

---

### C. `OrderItemShipGroup` (Fulfillment / Ship Group mapping)

POS orders have **no shipping** — the ship group represents in-store counter fulfillment:

| `OrderItemShipGroup` Field | Value | Source in Shopify JSON |
|---|---|---|
| `shipGroupSeqId` | `00001` | Auto-generated (single ship group) |
| `facilityId` | Facility mapped from `87821025411` | `order.retailLocation.legacyResourceId` |
| `shipmentMethodTypeId` | `POS_COMPLETED` / `NO_SHIPPING` | Inferred: `shippingLines = []` + `sourceName = "pos"` |
| `carrierPartyId` | `_NA_` | No carrier for POS |
| `shipByDate` | `null` | Immediate fulfillment at counter |
| `contactMechId` | `null` | `shippingAddress = null` |
| `telecomNumber` | `null` | `phone = null` |

#### `OrderItemShipGroupAssoc` (Line items linked to Ship Group)

| `orderItemSeqId` | `productId` | `SKU` | `quantity` | Source |
|---|---|---|---|---|
| `00001` | Mapped from SKU `265-102-G` | `265-102-G` | `1` | `lineItems[0]` |
| `00002` | Mapped from SKU `GWP-042` | `GWP-042` | `1` | `lineItems[1]` |

---

## 4. Fulfillment Confirmation

| Field | Value | Source |
|---|---|---|
| Shopify Fulfillment ID | `5962827268227` | `order.fulfillments[0].legacyResourceId` |
| Fulfilled At Location | `87821025411` | `fulfillments[0].location.legacyResourceId` |
| Items Fulfilled | Line Item `15455405801603` (qty 1) + `15455405834371` (qty 1) | `fulfillmentLineItems[]` |
| OMS `ItemIssuance` | Created after fulfillment sync | Triggered by `displayFulfillmentStatus = FULFILLED` |

---

## 5. Summary: POS Identification Checklist

```
Shopify → sourceName == "pos"                          ✅ PRIMARY
Shopify → retailLocation (non-null)                    ✅ SECONDARY
Shopify → shippingLines == []                          ✅ SUPPORTING
Shopify → shippingAddress == null                      ✅ SUPPORTING
Shopify → transaction.receiptJson.card_source == "stripe_terminal"  ✅ PAYMENT TYPE
Shopify → displayFulfillmentStatus == "FULFILLED"      ✅ IMMEDIATE FULFILLMENT

OMS     → Order.salesChannelEnumId == POS_SALES_CHANNEL             ✅ PRIMARY
OMS     → OrderAttribute[SOURCE_NAME] == "pos"                      ✅ SECONDARY
OMS     → OrderItemShipGroup.facilityId == store facility            ✅ STORE LINK
OMS     → OrderItemShipGroup.shipmentMethodTypeId == POS_COMPLETED   ✅ FULFILLMENT TYPE
```
