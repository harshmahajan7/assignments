# 📦 OFBiz Product Data Model — Part 2B: Price, Promo & Cost Entities

---

## SECTION A — PRODUCT PRICE ENTITIES

### Price Hierarchy
```
ProductPriceType ──► ProductPrice ◄── ProductPricePurpose
                          │
                   ProductPriceChange (audit log)

ProductPriceRule ──► ProductPriceCond (conditions)
                 └── ProductPriceAction (actions/adjustments)
```

---

## 1. `ProductPrice` — Price Record

The **core pricing entity**. Each row is a specific price for a product under given conditions.

| Field | Description |
|-------|-------------|
| `productId` 🔑 | The product |
| `productPriceTypeId` 🔑 | Price type (List, Default, Wholesale, etc.) |
| `productPricePurposeId` 🔑 | Purpose (Purchase, Component, etc.) |
| `currencyUomId` 🔑 | Currency (USD, EUR, INR…) |
| `productStoreGroupId` 🔑 | Store group this price applies to |
| `fromDate` 🔑 | Effective start date |
| `thruDate` | Effective end date (null = currently active) |
| `price` | The actual price amount |
| `termUomId` | Unit of time for term-based pricing (e.g., monthly subscription) |
| `customPriceCalcService` | Custom Groovy/Java service to dynamically compute price |
| `priceWithTax` | Pre-computed price including tax |
| `priceWithoutTax` | Pre-computed price excluding tax |
| `taxAmount` | Tax amount included |
| `taxPercentage` | Tax rate percentage |
| `taxAuthPartyId` | Tax authority party |
| `taxAuthGeoId` | Tax authority geography (state, country) |
| `createdDate` | When record was created |
| `createdByUserLogin` | Who created it |
| `lastModifiedDate` | Last update timestamp |
| `lastModifiedByUserLogin` | Who last modified it |

> **Multiple prices per product** — same product can have a List Price, Wholesale Price, Default Price, etc., all active simultaneously with different `productPriceTypeId`.

---

## 2. `ProductPriceType` — Price Type

Defines the **category/label** of a price.

| Field | Description |
|-------|-------------|
| `productPriceTypeId` 🔑 | Unique type ID |
| `description` | Human-readable label |

**Built-in Types:**

| ID | Meaning |
|----|---------|
| `DEFAULT_PRICE` | Standard selling price used when no other applies |
| `LIST_PRICE` | MSRP / advertised "was" price |
| `MINIMUM_PRICE` | Floor — system will not sell below this |
| `MAXIMUM_PRICE` | Ceiling — system will not sell above this |
| `AVERAGE_COST` | Average cost used for margin calculations |
| `COMPETITIVE_PRICE` | Competitor's price — used for comparison |
| `PROMO_PRICE` | Promotional price when promotion is active |
| `SPECIAL_PROMO_PRICE` | Special promo price set via promo rules |
| `WHOLESALE_PRICE` | B2B / wholesale price |

---

## 3. `ProductPricePurpose` — Price Purpose

Defines **what the price is used for** (purchasing, component costing, etc.).

| Field | Description |
|-------|-------------|
| `productPricePurposeId` 🔑 | Unique purpose ID |
| `description` | Label |

**Built-in Purposes:**

| ID | Meaning |
|----|---------|
| `PURCHASE` | Price for purchasing (standard) |
| `COMPONENT_PRICE` | Price used in BOM cost calculations |
| `RECURRING_CHARGE` | Price for recurring charges (subscriptions) |
| `ONE_TIME_CHARGE` | One-time charge at order time |

---

## 4. `ProductPriceChange` — Price Change Audit Log

Records the **history of every price change** — who changed it, when, and from what to what.

| Field | Description |
|-------|-------------|
| `productPriceChangeId` 🔑 | Unique audit record ID |
| `productId` | The product |
| `productPriceTypeId` | Which price type changed |
| `productPricePurposeId` | Purpose |
| `currencyUomId` | Currency |
| `productStoreGroupId` | Store group |
| `fromDate` | Effective date of the changed price |
| `thruDate` | End date of the changed price |
| `price` | **New** price value |
| `oldPrice` | **Previous** price value |
| `changedDate` | Timestamp of when change was made |
| `changedByUserLogin` | Who made the change |

---

## 5. `ProductPriceRule` — Price Rule

Defines an **automated pricing rule** with conditions + actions. When conditions match, the action adjusts the price.

| Field | Description |
|-------|-------------|
| `productPriceRuleId` 🔑 | Unique rule ID |
| `ruleName` | Descriptive name (e.g., "Holiday 10% Off") |
| `description` | Detailed explanation |
| `isSale` | Y = this rule creates a "sale" price |
| `fromDate` | When rule becomes active |
| `thruDate` | When rule expires |

---

## 6. `ProductPriceCond` — Price Rule Condition

**Condition** that must be true for a price rule to fire.

| Field | Description |
|-------|-------------|
| `productPriceRuleId` 🔑 | Parent rule |
| `productPriceCondSeqId` 🔑 | Sequence ID (multiple conditions per rule) |
| `inputParamEnumId` | **What to evaluate** (quantity, order total, product category, etc.) |
| `operatorEnumId` | **Comparison operator** |
| `condValue` | **Value to compare against** |

**Operators:**

| ID | Meaning |
|----|---------|
| `PRC_EQ` | Is Equal To |
| `PRC_NEQ` | Is Not Equal To |
| `PRC_LT` | Is Less Than |
| `PRC_LTE` | Is Less Than or Equal To |
| `PRC_GT` | Is Greater Than |
| `PRC_GTE` | Is Greater Than or Equal To |

**Quantity Break Types** (input params):
- `ORDER_VALUE` — total order value
- `QUANTITY` — product quantity
- `SHIP_PRICE` — shipping price
- `SHIP_QUANTITY` — shipping quantity
- `SHIP_WEIGHT` — shipping weight

---

## 7. `ProductPriceAction` — Price Rule Action

**What happens** when a price rule's conditions are met.

| Field | Description |
|-------|-------------|
| `productPriceRuleId` 🔑 | Parent rule |
| `productPriceActionSeqId` 🔑 | Sequence ID |
| `productPriceActionTypeId` | Type of adjustment |
| `amount` | The adjustment amount or percentage |
| `rateCode` | Optional rate code for complex calculations |

**Action Types:**

| ID | Meaning |
|----|---------|
| `PRICE_FOL` | Flat Amount Modify — add/subtract fixed amount |
| `PRICE_FLAT` | Flat Amount Override — set to exact amount |
| `PRICE_POAC` | Percent of Average Cost |
| `PRICE_POD` | Percent of Default Price |
| `PRICE_POL` | Percent of List Price |
| `PRICE_POM` | Percent of Margin |
| `PRICE_PFLAT` | Promo Amount Override |
| `PRICE_WFLAT` | Wholesale Amount Override |

---

## 8. `ProductPaymentMethodType` — Payment Method Pricing

Links specific **payment method types** to specific **price purposes** for a product (e.g., credit card = one price, check = another).

| Field | Description |
|-------|-------------|
| `productId` 🔑 | Product |
| `paymentMethodTypeId` 🔑 | Payment type (CREDIT_CARD, CHECK, etc.) |
| `productPricePurposeId` 🔑 | Price purpose |
| `fromDate` 🔑 | Effective start |
| `thruDate` | Effective end |
| `sequenceNum` | Priority order |

---

## SECTION B — PRODUCT PROMOTION ENTITIES

### Promo Hierarchy
```
ProductPromo
    ├── ProductPromoCode (coupon codes)
    ├── ProductPromoRule
    │       ├── ProductPromoCond (conditions)
    │       └── ProductPromoAction (actions)
    ├── ProductPromoProduct (specific products in promo)
    ├── ProductPromoCategory (category-level promo)
    ├── ProductPromoContent (promo images/text)
    └── ProductPromoUse (usage tracking)
```

---

## 9. `ProductPromo` — Promotion Definition

The **master promotion record**.

| Field | Description |
|-------|-------------|
| `productPromoId` 🔑 | Unique promo ID |
| `promoName` | Name (e.g., "Summer Sale 20% Off") |
| `promoText` | Customer-visible description text |
| `userEntered` | Y = promo was manually entered (not system-generated) |
| `showToCustomer` | Y = show this promo visibly to customer on site |
| `requireCode` | Y = customer must enter a coupon code to activate |
| `useLimitPerOrder` | Max times this promo can apply per single order |
| `useLimitPerCustomer` | Max times a single customer can ever use this promo |
| `useLimitPerPromotion` | Total max uses across ALL customers |
| `billbackFactor` | For supplier billback promos — percentage the supplier reimburses |
| `overrideOrgPartyId` | Override the default organization party for this promo |
| `createdDate` | Creation timestamp |
| `createdByUserLogin` | Who created it |
| `lastModifiedDate` | Last update timestamp |
| `lastModifiedByUserLogin` | Who last modified it |

---

## 10. `ProductPromoCode` — Coupon Code

A specific coupon code that activates a `ProductPromo`.

| Field | Description |
|-------|-------------|
| `productPromoCodeId` 🔑 | The code string (e.g., "SUMMER20") |
| `productPromoId` | Which promo this code activates |
| `userEntered` | Y = code was manually entered by user |
| `requireEmailOrParty` | Y = must have an account to use this code |
| `useLimitPerCode` | Max total uses of this specific code |
| `useLimitPerCustomer` | Max uses per customer for this code |
| `fromDate` | When code becomes valid |
| `thruDate` | When code expires |
| `createdDate` | Creation timestamp |
| `createdByUserLogin` | Who created it |
| `lastModifiedDate` | Last modified |
| `lastModifiedByUserLogin` | Who last modified |

---

## 11. `ProductPromoCodeEmail` — Allowed Emails for Code

Restricts a promo code to specific email addresses.

| Field | Description |
|-------|-------------|
| `productPromoCodeId` 🔑 | The promo code |
| `emailAddress` 🔑 | Email allowed to use this code |

---

## 12. `ProductPromoCodeParty` — Allowed Parties for Code

Restricts a promo code to specific parties (customers).

| Field | Description |
|-------|-------------|
| `productPromoCodeId` 🔑 | The promo code |
| `partyId` 🔑 | The customer allowed to use this code |

---

## 13. `ProductPromoRule` — Promotion Rule

Each promo can have **multiple rules**. Each rule has its own conditions + actions.

| Field | Description |
|-------|-------------|
| `productPromoId` 🔑 | Parent promo |
| `productPromoRuleId` 🔑 | Rule sequence ID |
| `ruleName` | Description of this rule |

---

## 14. `ProductPromoCond` — Promotion Condition

Condition that must be met for a promo rule to fire.

| Field | Description |
|-------|-------------|
| `productPromoId` 🔑 | Promo |
| `productPromoRuleId` 🔑 | Rule |
| `productPromoCondSeqId` 🔑 | Condition sequence |
| `inputParamEnumId` | **What to evaluate** |
| `operatorEnumId` | **Comparison** |
| `condValue` | **Threshold value** |
| `otherValue` | Secondary comparison value |

**Input Parameters (`PPIP_*`):**

| ID | Meaning |
|----|---------|
| `PPIP_ORDER_TOTAL` | Cart subtotal |
| `PPIP_PRODUCT_QUANT` | Quantity of product in cart |
| `PPIP_PRODUCT_AMOUNT` | Amount of product in cart |
| `PPIP_PRODUCT_TOTAL` | Total amount of product |
| `PPIP_PARTY_ID` | Specific customer |
| `PPIP_PARTY_CLASS` | Customer classification group |
| `PPIP_PARTY_GRP_MEM` | Customer is member of a party group |
| `PPIP_ROLE_TYPE` | Customer's role type |
| `PPIP_ORST_HIST` | Order subtotal in last X months |
| `PPIP_NEW_ACCT` | Account days since creation |

---

## 15. `ProductPromoAction` — Promotion Action

What discount/benefit is given when conditions are met.

| Field | Description |
|-------|-------------|
| `productPromoId` 🔑 | Promo |
| `productPromoRuleId` 🔑 | Rule |
| `productPromoActionSeqId` 🔑 | Action sequence |
| `productPromoActionEnumId` | Type of action |
| `orderAdjustmentTypeId` | How to apply it to the order |
| `quantity` | Quantity to apply action to |
| `amount` | Discount amount or percentage |
| `productId` | Specific product to give (for GWP) |
| `partyId` | Party to associate |
| `serviceName` | Custom service to call |
| `useCartQuantity` | Y = use actual cart quantity |

**Action Types (`PROMO_*`):**

| ID | Meaning |
|----|---------|
| `PROMO_GWP` | Gift With Purchase — free product added |
| `PROMO_ORDER_AMOUNT` | Flat amount off entire order |
| `PROMO_ORDER_PERCENT` | Percentage off entire order |
| `PROMO_PROD_DISC` | X product for Y% discount |
| `PROMO_PROD_AMDISC` | X product for Y amount discount |
| `PROMO_PROD_PRICE` | X product for Y specific price |
| `PROMO_PROD_SPPRC` | Product for special promo price |

---

## 16. `ProductPromoProduct` — Products in Promo Rule

Specifies which **individual products** a promo rule applies to.

| Field | Description |
|-------|-------------|
| `productPromoId` 🔑 | Promo |
| `productPromoRuleId` 🔑 | Rule |
| `productPromoCondSeqId` 🔑 | Condition or action it applies to |
| `productPromoActionSeqId` 🔑 | Action reference |
| `productId` 🔑 | The specific product |
| `productPromoApplEnumId` | Include / Exclude / Always Include |

**Application Enum:**

| ID | Meaning |
|----|---------|
| `PPPA_INCLUDE` | Include this product |
| `PPPA_EXCLUDE` | Exclude this product |
| `PPPA_ALWAYS` | Always apply regardless |

---

## 17. `ProductPromoCategory` — Categories in Promo Rule

Applies a promo rule to an entire **product category**.

| Field | Description |
|-------|-------------|
| `productPromoId` 🔑 | Promo |
| `productPromoRuleId` 🔑 | Rule |
| `productPromoCondSeqId` 🔑 | Condition reference |
| `productPromoActionSeqId` 🔑 | Action reference |
| `productCategoryId` 🔑 | The category |
| `andGroupId` 🔑 | AND grouping (for AND logic across conditions) |
| `productPromoApplEnumId` | Include / Exclude / Always |
| `includeSubCategories` | Y = apply to all sub-categories too |

---

## 18. `ProductPromoUse` — Promo Usage Tracking

Records every **actual use** of a promotion.

| Field | Description |
|-------|-------------|
| `orderId` 🔑 | Order where promo was used |
| `promoSequenceId` 🔑 | Sequence of use on that order |
| `productPromoId` | Which promo was used |
| `productPromoCodeId` | Which code was entered (if any) |
| `partyId` | Customer who used it |
| `totalDiscountAmount` | Total discount given |
| `quantityLeftInActions` | Remaining usage quantity in actions |

---

## 19. `ProductPromoContent` — Promo Media/Content

Attaches images or text content to a promotion.

| Field | Description |
|-------|-------------|
| `productPromoId` 🔑 | The promo |
| `productPromoContentTypeId` 🔑 | Type of content |
| `contentId` | The content record |
| `fromDate` | Active from |
| `thruDate` | Active until |

---

## SECTION C — COST ENTITIES

---

## 20. `CostComponentType` — Cost Component Type

Classifies the **type of cost component**.

| Field | Description |
|-------|-------------|
| `costComponentTypeId` 🔑 | Unique type ID |
| `parentTypeId` | Parent type |
| `hasTable` | Y = extra detail table exists |
| `description` | Label |

**Built-in Types:**

| ID | Meaning |
|----|---------|
| `ACTUAL_LABOR_COST` | Actual Labor Cost |
| `ACTUAL_MAT_COST` | Actual Materials Cost |
| `ACTUAL_OTHER_COST` | Actual Other Cost |
| `ACTUAL_ROUTE_COST` | Actual Route/Fixed Asset Usage Cost |
| `EST_STD_LABOR_COST` | Estimated Standard Labor Cost |
| `EST_STD_MAT_COST` | Estimated Standard Materials Cost |
| `EST_STD_OTHER_COST` | Estimated Standard Other Cost |
| `EST_STD_ROUTE_COST` | Estimated Standard Route Cost |
| `LABOR_COST` | General Labor Cost |
| `MAT_COST` | General Materials Cost |
| `OTHER_COST` | Other Cost |
| `ROUTE_COST` | Route Cost |

---

## 21. `CostComponent` — Actual Cost Record

Records a **specific cost** associated with a product, work effort, or fixed asset.

| Field | Description |
|-------|-------------|
| `costComponentId` 🔑 | Unique cost record ID |
| `costComponentTypeId` | Type of cost |
| `productId` | Product this cost applies to |
| `productFeatureId` | Feature this cost applies to (optional) |
| `partyId` | Party (supplier/employee) associated with cost |
| `geoId` | Geographic region for this cost |
| `workEffortId` | Work effort (production run) this cost is part of |
| `fixedAssetId` | Fixed asset (machine) used |
| `costComponentCalcId` | Reference to a cost calculation rule |
| `fromDate` | When cost is effective |
| `thruDate` | When cost expires |
| `cost` | The cost amount |
| `costUomId` | Currency/unit of the cost |

---

## 22. `CostComponentAttribute` — Extra Cost Attributes

Key-value extension attributes for a cost component.

| Field | Description |
|-------|-------------|
| `costComponentId` 🔑 | The cost record |
| `attrName` 🔑 | Attribute name |
| `attrValue` | Attribute value |
| `attrDescription` | Description |

---

## 23. `CostComponentTypeAttr` — Attribute Definitions per Cost Type

Defines which attributes are valid for each cost type.

| Field | Description |
|-------|-------------|
| `costComponentTypeId` 🔑 | The cost type |
| `attrName` 🔑 | Valid attribute name |
| `description` | Description of the attribute |

---

## 24. `ProductCostComponentCalc` — Cost Calculation Rule for Product

Links a product to a cost calculation method.

| Field | Description |
|-------|-------------|
| `productId` 🔑 | The product |
| `costComponentTypeId` 🔑 | Which cost type this calc applies to |
| `costComponentCalcId` | The calculation method/rule |
| `sequenceNum` | Evaluation order |
| `fromDate` 🔑 | Effective start |
| `thruDate` | Effective end |

---

## 25. `QuantityBreak` — Quantity Break Tiers

Defines **quantity/value tiers** used in price or shipping break rules.

| Field | Description |
|-------|-------------|
| `quantityBreakId` 🔑 | Unique break ID |
| `quantityBreakTypeId` | Type of break (ORDER_VALUE, QUANTITY, SHIP_PRICE, SHIP_QUANTITY, SHIP_WEIGHT) |
| `fromQuantity` | Tier start quantity/amount |
| `thruQuantity` | Tier end quantity/amount |

---

## 🗺️ Complete Price/Promo/Cost Relationship Map

```
ProductPriceType ──► ProductPrice ◄── ProductPricePurpose
                          │               │
                   ProductPriceChange  ProductPaymentMethodType
                          
ProductPriceRule ──► ProductPriceCond
                 └── ProductPriceAction ──► ProductPriceActionType

ProductPromo ──► ProductPromoCode ──► ProductPromoCodeEmail
            │                    └── ProductPromoCodeParty
            ├── ProductPromoRule ──► ProductPromoCond
            │                   └── ProductPromoAction
            ├── ProductPromoProduct
            ├── ProductPromoCategory
            ├── ProductPromoContent
            └── ProductPromoUse

CostComponentType ──► CostComponent ──► CostComponentAttribute
ProductCostComponentCalc ──► CostComponent
```
