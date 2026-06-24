# Shopify Order Import — Complete Flow Reference

> **Scope:** Full trace from Job Scheduler → DataManager → Shopify Connector → OMS Order Creation → DB persistence.  
> Merges MDM, Shopify import, and order creation data into one reference.

---

## 1. High-Level Architecture

```
Job Scheduler (ServiceJob)
        │
        ▼
processPendingDataManagerJob          ← MDM Entry Point
        │   reads: DataManagerConfig (configId = CRT_SHOPIFY_ORDER)
        │   reads: DataManagerLog     (finds PENDING files)
        │
        ▼
uploadAndImportFile / importDataFromJSON   ← DataImportServices.java
        │   determines: importService = "createShopifyOrder"
        │   updates: DataManagerLog (status → RUNNING)
        │
        ▼
createShopifyOrder                    ← ShopifyOrderServices.java
        │   reads:  ShopifyConfig, ShopifyShop
        │   filters: order tags
        │   maps:   channel, productStoreId, externalId
        │
        ▼
createSalesOrder                      ← OrderServices.java (api component)
        │   validates: JSON schema (CreateSalesOrder.json)
        │   checks:   duplicate externalId in OrderHeader
        │
        ▼
OFBiz Entity Persistence              ← delegator.create() / storeAll()
        │
        ├── OrderHeader
        ├── OrderItem
        ├── OrderItemShipGroup
        ├── OrderAdjustment
        ├── OrderContactMech
        ├── OrderRole
        └── OrderStatus
```

---

## 2. Stage-by-Stage Flow

### Stage 1 — Job Scheduling
| What Happens | Details |
|---|---|
| A scheduled job fires | `ServiceJob` entity triggers the service `processPendingDataManagerJob` |
| Config lookup | Reads `DataManagerConfig` for `configId = CRT_SHOPIFY_ORDER` |
| Log lookup | Reads `DataManagerLog` where `statusId = SERVICE_PENDING` |
| File picked | The pending file path (Shopify JSON) is resolved |

---

### Stage 2 — MDM Processing (`DataImportServices.java`)
| Method | What it does |
|---|---|
| `processPendingDataManagerJob` | Fetches pending `DataManagerLog` records; triggers import |
| `uploadAndImportFile` | Saves uploaded file; creates/updates `DataManagerLog`; queues job |
| `importDataFromJSON` | Reads JSON file; calls configured import service per record |
| `getImportServiceName` | Detects MIME type (`application/json`) → returns `"createShopifyOrder"` |

---

### Stage 3 — Shopify Connector (`ShopifyOrderServices.java`)
| Method | What it does |
|---|---|
| `importShopifyOrders` | Fetches orders from Shopify API; converts to `ByteBuffer`; calls `uploadAndImportFile` |
| `createShopifyOrder` | Parses one Shopify order JSON; skips based on tags; maps fields; calls `createSalesOrder` |

Key field mappings done inside `createShopifyOrder`:
- `order.id` → `externalId`
- Shopify `source_name` → OMS `salesChannel`
- Shopify `email` → `OrderContactMech`
- Line items → `OrderItem` list
- Discounts / shipping → `OrderAdjustment` list
- Shipping address → `OrderContactMech` (SHIPPING_LOCATION)
- Billing address → `OrderContactMech` (BILLING_LOCATION)

---

### Stage 4 — OMS Order Creation (`OrderServices.java`)
| Method | What it does |
|---|---|
| `createSalesOrder` | Validates input, checks duplicate `externalId`, creates order header |
| `updateSalesOrder` | Updates existing order header, items, adjustments |

---

## 3. DB Tables Involved — Complete Table

| # | Table (Entity) | Stage | Service That Writes | Role / What's Stored |
|---|---|---|---|---|
| 1 | `ServiceJob` | Scheduling | OFBiz Job Scheduler | Holds the job definition for `processPendingDataManagerJob` |
| 2 | `RuntimeData` | Scheduling | OFBiz Job Scheduler | Stores job runtime parameters (jobParameters as XML/map) |
| 3 | `DataManagerConfig` | MDM Config | Seed Data (read-only) | Holds `configId`, `importService`, `importPath`, `ftpConfigId` |
| 4 | `DataManagerLog` | MDM Processing | `uploadAndImportFile` | Tracks each import attempt — status, file path, timestamps, error msg |
| 5 | `DataManagerMapping` | MDM Config | Seed Data (read-only) | Maps field names between source (Shopify) and target (OFBiz) |
| 6 | `ContentData` | MDM File Storage | `uploadAndImportFile` | Stores the actual Shopify JSON file as a `ByteBuffer` blob |
| 7 | `Content` | MDM File Storage | `uploadAndImportFile` | Metadata record linking to `ContentData` |
| 8 | `OrderHeader` | Order Creation | `createSalesOrder` | Core order record — `orderId`, `externalId`, `statusId`, `grandTotal`, `productStoreId`, `salesChannelEnumId`, `orderDate` |
| 9 | `OrderItem` | Order Creation | `createSalesOrder` | Each line item — `productId`, `quantity`, `unitPrice`, `externalId` (Shopify line item ID) |
| 10 | `OrderItemShipGroup` | Order Creation | `createSalesOrder` | Groups items by ship-to address / shipping method |
| 11 | `OrderItemShipGroupAssoc` | Order Creation | `createSalesOrder` | Associates `OrderItem` with a ship group |
| 12 | `OrderAdjustment` | Order Creation | `createSalesOrder` | Discounts, shipping charges, taxes — header-level and item-level |
| 13 | `OrderContactMech` | Order Creation | `createSalesOrder` | Shipping & billing addresses linked to order |
| 14 | `PostalAddress` | Order Creation | `createSalesOrder` | The actual address fields (street, city, state, postal code, country) |
| 15 | `OrderRole` | Order Creation | `createSalesOrder` | Associates `Party` (customer) with the order in `PLACING_CUSTOMER` role |
| 16 | `Party` | Order Creation | `createSalesOrder` | Customer party record (created if not exists) |
| 17 | `Person` | Order Creation | `createSalesOrder` | Customer name (first, last) linked to `Party` |
| 18 | `PartyContactMech` | Order Creation | `createSalesOrder` | Links contact info (email, phone) to customer `Party` |
| 19 | `ContactMech` | Order Creation | `createSalesOrder` | Email or phone contact mechanism |
| 20 | `OrderStatus` | Order Creation | `createSalesOrder` | Initial status history record — `ORDER_CREATED` |
| 21 | `OrderPaymentPreference` | Order Creation | `createSalesOrder` | Payment method preference linked to order |

---

## 4. MDM Services — Full Catalog

All services defined in `applications/hwmapps/servicedef/datamanager/services.xml`:

| Service Name | Engine | Export? | Description |
|---|---|---|---|
| `processPendingDataManagerJob` | java | No | Main job processor — picks pending files and runs import |
| `uploadAndImportFile` | java | No | Saves file + creates DataManagerLog + triggers async import |
| `importDataFromJSON` | java | No | Reads JSON file; iterates records; calls per-record import service |
| `orderDataSetup` | java | No | Sets up order-level data (customer, address) before item creation |
| `getDataManagerLogs` | groovy | **Yes** | REST API — fetch DataManagerLog records with filters |
| `getDataManagerConfig` | groovy | **Yes** | REST API — fetch DataManagerConfig details by configId |

---

## 5. Shopify Connector Services — Full Catalog

All services in `applications/shopify-connector/servicedef/services.xml`:

| Service Name | Engine | Description |
|---|---|---|
| `importShopifyOrders` | java | Pulls orders from Shopify API + triggers MDM upload |
| `createShopifyOrder` | java | Parses single Shopify order JSON → calls `createSalesOrder` |
| `updateShopifyOrder` | java | Handles Shopify order update webhooks |
| `createOrdersFromShopify` | java | Batch creation of orders from Shopify feed |

---

## 6. OMS Order Services — Full Catalog

Services in `applications/api/servicedef/services.xml` / `OrderServices.java`:

| Service Name | Engine | Description |
|---|---|---|
| `createSalesOrder` | java | Core order creation — validates + persists full order |
| `updateSalesOrder` | java | Updates order header, items, adjustments |

---

## 7. MDM Data Model — Entities

### `DataManagerConfig`
| Field | Type | Description |
|---|---|---|
| `configId` | PK | Unique config ID (e.g., `CRT_SHOPIFY_ORDER`) |
| `description` | String | Human-readable label |
| `importPath` | String | File path where import files are placed |
| `exportPath` | String | Path for export files |
| `ftpConfigId` | FK | Reference to FTP/SFTP config |
| `importService` | String | Service to call for each record (e.g., `createShopifyOrder`) |

### `DataManagerLog`
| Field | Type | Description |
|---|---|---|
| `logId` | PK (seq) | Auto-generated log ID |
| `configId` | FK | Links to `DataManagerConfig` |
| `statusId` | Enum | `SERVICE_PENDING` → `SERVICE_RUNNING` → `SERVICE_FINISHED` / `SERVICE_FAILED` |
| `importPath` | String | Actual file path being processed |
| `jobId` | FK | OFBiz job scheduler job ID |
| `createdDate` | Timestamp | When log was created |
| `processedDate` | Timestamp | When import completed |
| `errorMessage` | String | Error detail if failed |

### `DataManagerMapping`
| Field | Type | Description |
|---|---|---|
| `mappingId` | PK | Unique ID |
| `configId` | FK | Links to `DataManagerConfig` |
| `sourceField` | String | Source field name (Shopify payload field) |
| `targetField` | String | OFBiz target entity field |

---

## 8. Key Configuration — `CRT_SHOPIFY_ORDER`

Defined in `applications/shopify-connector/data/ShopifyData.xml`:

```xml
<DataManagerConfig configId="CRT_SHOPIFY_ORDER"
    description="Create Shopify Orders"
    importService="createShopifyOrder"
    importPath="/downloads/shopify/order"
    ftpConfigId="SHOPIFY_SFTP"/>
```

---

## 9. Complete Service Call Chain (Sequential)

```
[Job Scheduler]
  → processPendingDataManagerJob (DataImportServices.java)
      reads: DataManagerConfig[CRT_SHOPIFY_ORDER]
      reads: DataManagerLog[statusId=SERVICE_PENDING]
      updates: DataManagerLog[statusId=SERVICE_RUNNING]

  → importDataFromJSON (DataImportServices.java)
      reads: Content, ContentData (Shopify JSON file)
      calls: getImportServiceName() → "createShopifyOrder"
      [for each order in JSON array]:

        → createShopifyOrder (ShopifyOrderServices.java)
            reads: ShopifyConfig, ShopifyShop
            filters: order tags
            builds: order context map

          → createSalesOrder (OrderServices.java)
              validates: JSON schema (CreateSalesOrder.json)
              checks: OrderHeader[externalId] (duplicate prevention)
              creates: OrderHeader
              creates: OrderItem (per line item)
              creates: OrderItemShipGroup
              creates: OrderItemShipGroupAssoc
              creates: OrderAdjustment (discounts, shipping, tax)
              creates: OrderContactMech + PostalAddress (shipping/billing)
              creates: OrderRole (PLACING_CUSTOMER)
              creates: Party + Person (if new customer)
              creates: OrderStatus (ORDER_CREATED)

  updates: DataManagerLog[statusId=SERVICE_FINISHED or SERVICE_FAILED]
```

---

## 10. REST API Endpoints (MDM)

Both endpoints use dynamic routing via `JsonApiEvents.processApiCall`:

| Endpoint | Method | Auth | Description |
|---|---|---|---|
| `/api/control/service/getDataManagerLogs` | POST | Bearer / API Key | Fetch import logs with filters |
| `/api/control/service/getDataManagerConfig` | POST | Bearer / API Key | Fetch config details |

Only services with `export="true"` are callable externally.

---

## 11. Key File Locations Reference

| Component | File |
|---|---|
| MDM Services (Java) | `applications/hwmapps/src/main/java/co/hotwax/datamanager/DataImportServices.java` |
| MDM Service Defs | `applications/hwmapps/servicedef/datamanager/services.xml` |
| MDM Groovy Scripts | `applications/hwmapps/groovyScripts/commerce/datamanager/DataManagerServices.groovy` |
| MDM Entity Defs | `applications/hwmapps/entitydef/entitymodel.xml` |
| MDM Docs | `applications/hwmapps/docs/DataManagerConfig.md` |
| MDM Util | `applications/hwmapps/src/main/java/co/hotwax/datamanager/DataImportUtil.java` |
| Shopify Services (Java) | `applications/shopify-connector/src/main/java/co/hotwax/shopify/order/ShopifyOrderServices.java` |
| Shopify Service Defs | `applications/shopify-connector/servicedef/services.xml` |
| Shopify Seed Data | `applications/shopify-connector/data/ShopifyData.xml` |
| OMS Order Services | `applications/api/src/main/java/co/hotwax/oms/OrderServices.java` |
| OMS Service Defs | `applications/api/servicedef/services.xml` |
| Order Schema | `applications/api/schemas/oms/CreateSalesOrder.json` |
| REST Router | `applications/hwmapps/src/main/java/co/hotwax/common/JsonApiEvents.java` |
| Auth Filter | `applications/hwmapps/src/main/java/co/hotwax/common/ApiFilter.java` |
| API Controller | `applications/api/webapp/api/WEB-INF/controller.xml` |
