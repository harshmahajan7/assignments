# 📋 Problem Statement: Order Flow & MDM Pre-Processing Exploration

> **Task for:** Internship Exploration / Code Study
> **Source:** Meeting notes (raw → refined)
> **Scope:** Shopify → HotWax OMS order import flow, excluding Returns & Exchanges

---

## ✅ Corrected & Refined Problem Statement

**"Study and document the order flow from Shopify into HotWax Commerce (OMS), specifically the phase where the order goes into the MDM (Master Data Manager / delegator layer) for processing BEFORE the order record is officially created in the database. Trace the service code that handles this flow. Identify all entities that are created or touched during this process, with a special focus on entities that have static/seed data such as Enums, Types, and Status values. Additionally, identify all types of identifications (IDs) associated with an order — particularly those coming from the Shopify integration. Do NOT include order returns or exchanges in this scope."**

---

## 🔍 What Is the Task Broken Down Into?

Your task has **5 main exploration areas**:

---

### 1️⃣ Order Flow: Shopify → OMS (Pre-Creation Phase)

**What to study:**
When a Shopify order is downloaded, it goes through a multi-step process BEFORE the order is actually saved (`storeOrder` / `createOrder` service). That pre-processing phase is what you need to trace.

**The Flow (High-Level):**

```
Shopify API (JSON)
      ↓
Job: "New Orders" / "Import Orders in Bulk"
      ↓
JSON file stored on filesystem
      ↓
File processing job reads JSON
      ↓
[PRE-CREATION / MDM PHASE ← YOUR FOCUS]
  → Parse JSON to Java/Groovy objects
  → Map Shopify fields → OFBiz entity fields
  → Build ShoppingCart or Value maps in memory
  → Validate data (duplicate check, product lookup, party lookup)
  → Prepare OrderHeader, OrderItems, Adjustments, Payment Prefs, Roles, etc.
      ↓
createOrder() / storeOrder() service called
      ↓
ORDER CREATED in DB (status = "Created")
      ↓
Order Approval → Brokering → Fulfillment
```

**Key Point:** The MDM pre-processing phase is where all the data is assembled in memory using the **Delegator** (OFBiz's data access layer). This is the phase BEFORE `delegator.storeAll()` is called.

---

### 2️⃣ Service Code Trace (Order Creation)

**Primary service to trace:**
```
org.apache.ofbiz.order.order.OrderServices → createOrder()
```
**File location:**
```
ofbiz-framework/applications/order/src/main/java/org/apache/ofbiz/order/order/OrderServices.java
```

**Service call chain (simplified):**
```
storeOrder (services.xml)
  └→ createOrderFromShoppingCart
       └→ createOrder()
            ├── OrderHeader          ← created first
            ├── OrderItem            ← per line item
            ├── OrderItemShipGroup   ← shipping group
            ├── OrderAdjustment      ← discounts, taxes, shipping fees
            ├── OrderRole            ← PLACING_CUSTOMER, SHIP_TO_CUSTOMER, etc.
            ├── OrderPaymentPreference ← payment method
            ├── OrderContactMech     ← shipping/billing address
            ├── OrderItemPriceInfo   ← price calculation detail
            ├── OrderItemShipGroupAssoc ← item ↔ ship group link
            └── WorkOrderItemFulfillment ← if rental/work effort
```

**Service definitions file:**
```
applications/order/servicedef/services.xml        ← main service defs
applications/order/servicedef/services_order.xml  ← CRUD services for order sub-entities
```

---

### 3️⃣ Order Identifications (from Shopify Integration)

**"Identification" kya hoti hai ek order ke liye?**

Ek single Shopify order ke liye multiple IDs aati hain:

| # | ID Name | Description | Entity/Field |
|---|---------|-------------|-------------|
| 1 | **OMS Order ID** | HotWax internal order ID | `OrderHeader.orderId` |
| 2 | **Shopify Order ID** | Shopify's numeric order ID | `OrderIdentification` or `OrderAttribute` |
| 3 | **Shopify Order Name** | Human-readable e.g. `#1001` | `OrderHeader.orderName` |
| 4 | **Shopify Shop (Product Store ID)** | Which store the order came from | `OrderHeader.productStoreId` |
| 5 | **External ID** | externalId field on OrderHeader/Item | `OrderHeader.externalId` |
| 6 | **First Attempt Order ID** | Original order if re-attempted | `OrderHeader.firstAttemptOrderId` |
| 7 | **Visit ID** | Web session ID | `OrderHeader.visitId` |
| 8 | **Web Site ID** | Source website | `OrderHeader.webSiteId` |
| 9 | **Origin Facility ID** | Source location/warehouse | `OrderHeader.originFacilityId` |
| 10 | **Billing Account ID** | Customer billing account | `OrderHeader.billingAccountId` |

> **Note:** `OrderIdentification` is an OFBiz entity specifically designed to store multiple external IDs for an order. This is where Shopify Order ID, POS ID, etc., would be stored with an `orderIdentificationTypeId`.

---

### 4️⃣ All Entities Per Order (Complete Data Model)

**Ek order se kitne types ka data store hota hai:**

#### 🟦 Core Order Entities
| Entity | Purpose |
|--------|---------|
| `OrderHeader` | Main order record — orderId, status, dates, totals, type |
| `OrderItem` | Each product line in the order |
| `OrderItemShipGroup` | Shipping group (ship-from location, method) |
| `OrderItemShipGroupAssoc` | Links items to ship groups |

#### 🟩 Financial / Pricing Entities
| Entity | Purpose |
|--------|---------|
| `OrderAdjustment` | Discounts, taxes, shipping fees, promos |
| `OrderItemPriceInfo` | Detailed price breakdown per item |
| `OrderItemBilling` | Links order items to invoices |
| `OrderAdjustmentBilling` | Links adjustments to invoices |
| `OrderPaymentPreference` | Payment method used (credit card, gift card, etc.) |

#### 🟨 Party / Role Entities
| Entity | Purpose |
|--------|---------|
| `OrderRole` | Who is associated with the order (customer, vendor, etc.) |
| `OrderItemRole` | Role association at item level |

#### 🟧 Address / Contact Entities
| Entity | Purpose |
|--------|---------|
| `OrderContactMech` | Shipping & billing addresses |
| `OrderItemContactMech` | Item-level address override |

#### 🟥 Status & Tracking Entities
| Entity | Purpose |
|--------|---------|
| `OrderStatus` | History of status changes |
| `OrderHeader.statusId` | Current status |
| `OrderHeader.syncStatusId` | Sync status with external system |

#### 🟪 Identification & Attribute Entities
| Entity | Purpose |
|--------|---------|
| `OrderIdentification` | External IDs (Shopify ID, POS ID, etc.) |
| `OrderAttribute` | Key-value custom attributes |
| `OrderItemAttribute` | Key-value attributes at item level |

#### ⬛ Misc / Supporting Entities
| Entity | Purpose |
|--------|---------|
| `OrderHeaderNote` | Notes attached to order |
| `OrderItemGroup` | Groups of items (bundle, kit) |
| `OrderItemAssoc` | Associations between items |
| `OrderRequirementCommitment` | Purchase requisition links |
| `OrderProductPromoCode` | Applied promo codes |
| `OrderShipment` | Links order to actual shipment |
| `OrderHeaderWorkEffort` | Links order to work effort (rental) |
| `WorkOrderItemFulfillment` | Work effort ↔ order item link |

---

### 5️⃣ Entities with Static Data (Enums, Types, Status Values)

**Ye entities "seed data" ya "type tables" hain — inme pre-defined static values hote hain:**

#### 🏷️ Type Entities (Hierarchical)
| Type Entity | `*typeId` field | Example Values |
|-------------|----------------|---------------|
| `OrderType` | `orderTypeId` | `SALES_ORDER`, `PURCHASE_ORDER` |
| `OrderItemType` | `orderItemTypeId` | `PRODUCT_ORDER_ITEM`, `RENTAL_ORDER_ITEM`, `WORK_ORDER_ITEM` |
| `OrderAdjustmentType` | `orderAdjustmentTypeId` | `PROMOTION_ADJUSTMENT`, `SHIPPING_CHARGES`, `SALES_TAX`, `DISCOUNT_ADJUSTMENT` |
| `OrderItemAssocType` | `orderItemAssocTypeId` | Type of relationship between items |
| `OrderContentType` | `orderContentTypeId` | `IMAGE_URL`, `DOCUMENT` |

#### 📊 Status Entities (Enum-like)
| Status Category | `statusId` Examples |
|----------------|---------------------|
| **Order Status** (`ORDER_STATUS`) | `ORDER_CREATED`, `ORDER_APPROVED`, `ORDER_COMPLETED`, `ORDER_CANCELLED` |
| **Order Item Status** (`ITEM_STATUS`) | `ITEM_CREATED`, `ITEM_APPROVED`, `ITEM_COMPLETED`, `ITEM_CANCELLED` |
| **Payment Preference Status** | `PAYMENT_NOT_AUTH`, `PAYMENT_AUTHORIZED`, `PAYMENT_RECEIVED`, `PAYMENT_SETTLED` |
| **Sync Status** | `ORDER_SYNC_CREATED`, `ORDER_SYNC_FAILED` |

#### 🔢 Enumeration Entities
| Enum Type | `enumTypeId` | Used In |
|-----------|-------------|--------|
| Sales Channel | `ORDER_SALES_CHANNEL` | `OrderHeader.salesChannelEnumId` → e.g., `PHONE_SALES`, `WEB_SALES` |
| Order Denylist Type | `ORDER_DENYLIST_TYPE` | Fraud check categories |
| Shipment Method Type | `SHIPMENT_METHOD` | `OrderItemShipGroup.shipmentMethodTypeId` |

---

## 🔗 Where to Find The Code (File Map)

| What | File Path |
|------|-----------|
| **Order entity definitions** | `applications/datamodel/entitydef/order-entitymodel.xml` |
| **Order view entities** | `applications/order/entitydef/entitymodel_view.xml` |
| **Main order services (Java)** | `applications/order/src/main/java/.../order/OrderServices.java` |
| **Service definitions** | `applications/order/servicedef/services.xml` |
| **CRUD service defs** | `applications/order/servicedef/services_order.xml` |
| **Service Event Condition Actions** | `applications/order/servicedef/secas.xml` |
| **Order type seed data** | `applications/order/data/OrderTypeData.xml` |
| **Shopify order documentation** | `oms-documentation/documents/learn-shopify/shopify-integration/orders/order-download.md` |

---

## 🚫 What is OUT of Scope

Per the problem statement, **exclude:**
- `OrderReturn` and related entities (`ReturnHeader`, `ReturnItem`, `ReturnAdjustment`)
- Exchange flows
- All return-related services in `services_return.xml`

---

## 📝 Summary: What You Need to Deliver

| # | Deliverable |
|---|-------------|
| 1 | **Flow Diagram**: Shopify → JSON → MDM pre-processing → `createOrder()` |
| 2 | **Service Trace**: Step-by-step walkthrough of `createOrder()` method |
| 3 | **Order Identifications List**: All IDs stored per order (especially Shopify-originated) |
| 4 | **Entity Inventory**: All entities created/touched in the order creation flow |
| 5 | **Static Data Catalog**: All Type/Enum/Status entities with their static values |

---

## 💡 Key Terms Explained

| Term | Meaning |
|------|---------|
| **MDM** | In this context = **Master Data Manager** or **delegator** layer in OFBiz that handles DB operations. The "pre-MDM" phase is when data is assembled in memory before being stored. |
| **Enum / Type** | Static lookup values (like `OrderType`, `StatusItem`) — they don't change per transaction |
| **Identification** | External IDs (from Shopify, POS, etc.) associated with an OMS order |
| **storeOrder** | The OFBiz service that triggers the full order creation pipeline |
| **ShoppingCart** | The in-memory object that holds all order data before it is persisted |
| **delegator** | OFBiz's ORM layer — equivalent to a repository/DAO in Spring |

