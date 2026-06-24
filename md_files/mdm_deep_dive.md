# MDM (Master Data Manager) — Complete Deep Dive

## 1. What is MDM in HotWax / MAARG?

**MDM = Master Data Manager** — a HotWax-built internal framework (not a generic industry tool) running inside the **MAARG** (Moqui) application. It is a **file-based, configurable import/export pipeline** that:

- Receives files (JSON, CSV, JSONL) from any source (manual upload, SFTP, SQS, webhook, code)
- Routes each file to the correct processing service based on a **`DataManagerConfig`** record
- Tracks every operation in **`DataManagerLog`** with a full status lifecycle
- Runs processing jobs across **two dedicated thread pools** (Priority + Normal)
- Is the **central nervous system** for all bulk data flowing into and out of OFBiz-OMS

> In the Shopify order import context specifically, MDM is the **staging layer** between raw Shopify order data and the OMS order creation logic.

---

## 2. Core Entities (Data Model)

All entities live under package `co.hotwax.datamanager`.

### 2.1 `DataManagerConfig`
Defined in: `ofbiz-oms-udm/entity/HwmappsEntitymodel.xml`

The **master registry** — one row per integration type.

| Field | Type | Purpose |
|---|---|---|
| `configId` | id (PK) | Unique key, e.g. `SYNC_SHOPIFY_ORDER`, `MDM_PRODUCT` |
| `importServiceName` | text-medium | Service called to **process** the uploaded file |
| `exportServiceName` | text-medium | Service called to **export** data to a file |
| `exportContentId` | id | Content template used during export |
| `exportServiceScreenName` | text-medium | Screen name for export filter UI |
| `exportServiceScreenLocation` | text-medium | Screen XML path for export filters |
| `description` | text-medium | Human label |
| `scriptTitle` | text-medium | Label shown in job scheduler UI |
| `delimiter` | text-medium | CSV delimiter (if applicable) |
| `fileNamePattern` | text-medium | Pattern for generated file names (e.g. `Product_${sequence}`) |
| `executionModeId` | id | Enum: threading mode |
| `multiThreading` | indicator | `Y`/`N` — multi-thread import |
| `importPath` | text-medium | SFTP path for auto-pickup (e.g. `/home/{SFTP-USER}/hotwax/oms/...`) |
| `exportPath` | text-medium | SFTP path for auto-push |
| `priority` | number-integer | Job queue priority |
| `enableDataFeed` | indicator | `Y` = also triggers a DataFeed (webhook fan-out) |

**Extended by** `ShopifyConnectorEntitymodel.xml` to add:
- `notifyOnFailure` (indicator) — send alert if processing fails
- `enableDataFeed` (duplicated as override with default `N`)

---

### 2.2 `DataManagerLog`
The **audit trail** for every import/export operation. One row per file processed.

| Field | Type | Purpose |
|---|---|---|
| `logId` | id (PK, sequence) | Unique log ID |
| `parentLogId` | id | Links to parent log (batch/child relationship) |
| `configId` | id (FK → DataManagerConfig) | Which config ran |
| `ownerPartyId` | id | Party who triggered it |
| `uploadFileContentId` | id | Content record of the uploaded input file |
| `exportFileContentId` | id | Content record of the exported output file |
| `errorRecordContentId` | id | File with records that failed |
| `logFileContentId` | id | Execution log text file |
| `logTypeEnumId` | id (FK → Enumeration) | `DmltImport` or `DmltExport` |
| `statusId` | id (FK → StatusItem) | Lifecycle status (see below) |
| `createdByUserLogin` | id-long | Who triggered |
| `createdDate` | date-time | When |
| `runByInstanceId` | id | Which MAARG instance ran it (for multi-node) |
| `jobId` | id | ServiceJob that ran it |

**Extended by** `ShopifyConnectorEntitymodel.xml`:
- `shopifyConfigId` — which Shopify shop config this log belongs to
- `remoteFilePath` — path on the remote (SFTP/S3) where the file came from
- `namespace` — Shopify namespace (e.g. for metafields)

---

### 2.3 `DataManagerContent`
Defined in: `ofbiz-oms-udm/entity/OmsEntities.xml`

Tracks **each file artifact** associated with a log (uploaded file, error file, log file, export file).

| Field | Type | Purpose |
|---|---|---|
| `logContentId` | id (PK) | Unique content record |
| `logId` | id (FK → DataManagerLog) | Which log |
| `fileName` | text-medium | File name |
| `fileSize` | number-integer | Bytes |
| `contentLocation` | text-medium | Physical path (e.g. `runtime://datamanager/orders/raw/...`) |
| `logContentTypeEnumId` | id | `DmcntImported`, `DmcntExported`, `DmcntError`, `DmcntLog` |
| `description` | text-long | Description |
| `contentDate` | date-time | Auto-set to now |
| `userId` | id | Auto-set to current user |

---

### 2.4 `DataManagerParameter`
Stores **extra parameters** that get auto-injected into the import service call when a log runs. Stored as strings, type-converted at call time based on the service definition.

| Field | Purpose |
|---|---|
| `logId` + `parameterName` (PK) | Which log, which param |
| `parameterValue` | String value |

---

## 3. Status Lifecycle (Enums & StatusFlow)

### Log Type Enum (`DataManagerLog` EnumerationType)
| enumId | Code | Meaning |
|---|---|---|
| `DmltImport` | Import | This log is an import operation |
| `DmltExport` | Export | This log is an export operation |

### Status Flow (StatusType: `DataManagerLog`)
```
DmlsPending → DmlsQueued → DmlsRunning → DmlsFinished
                    ↓              ↓              
               DmlsFailed    DmlsCrashed
               DmlsCancelled DmlsCancelled
```

| statusId | Code | statusAge | Meaning |
|---|---|---|---|
| `DmlsPending` | PENDING | 25 | Created, not yet picked up |
| `DmlsQueued` | QUEUED | 25 | In worker pool queue |
| `DmlsRunning` | RUNNING | 75 | Actively processing |
| `DmlsFinished` | FINISHED | 100 | Completed successfully |
| `DmlsFailed` | FAILED | 101 | Service returned error |
| `DmlsCrashed` | CRASHED | 101 | JVM/thread died mid-run |
| `DmlsCancelled` | CANCELLED | 101 | Manually cancelled |

### Content Type Enum (`DataManagerContentType`)
| enumId | Meaning |
|---|---|
| `DmcntImported` | The uploaded/input file |
| `DmcntExported` | The generated export file |
| `DmcntError` | Records that failed processing |
| `DmcntLog` | Execution log text |

---

## 4. Worker Pools (Runtime Engine)

MDM runs with **two dedicated thread pools**, visible in the OMS UI at:
**`OMS → About`** screen (`oms/screen/Oms/About.xml`)

```groovy
// About.xml actions
import co.hotwax.mdm.ScheduledDataManagerRunner;
ScheduledDataManagerRunner mdmRunner = ec.factory.getTool("MDM", ScheduledDataManagerRunner)
mdmPriorityWorkerPool = mdmRunner?.priorityPool
mdmNormalWorkerPool   = mdmRunner?.normalPool
```

### Priority Pool
- Handles **high-urgency** imports (e.g. Shopify order sync — real-time customer orders)
- Configured via `DataManagerConfig.priority` field
- UI shows: Active threads / Pool size / Max size / Queue size / Remaining capacity

### Normal Pool
- Handles **bulk** or **background** imports (e.g. product catalog, inventory)
- Lower urgency, larger batch sizes

The UI renders both pools with **color-coded warnings**:
- 🟡 Warning: Active == Max (pool saturated)
- 🔴 Danger: Queue remaining == 0 (queue full, will drop jobs)

---

## 5. UI Surfaces for MDM

### 5.1 About Page (`/oms/About`)
Shows **live runtime health** of both MDM worker pools. Ops team uses this to check if MDM is keeping up with order volume.

### 5.2 DataManager Screen (in MAARG UI)
Path: `../../DataManager/DataManagerConfig/DataManagerConfigView`  
Referenced in: `shopify-oms-bridge/screen/ShopifyOmsBridge/ShopifyOrderIntegrationSetup.xml`

This is the **admin console** for MDM. Shows:
- List of all `DataManagerConfig` entries
- Per-config: import service, export service, file pattern
- Log history for each config
- Status of each log (PENDING → FINISHED)
- Links to download uploaded file, error file, log file

### 5.3 Shopify Order Integration Setup Screen
`shopify-oms-bridge/screen/ShopifyOmsBridge/ShopifyOrderIntegrationSetup.xml`

Has a dedicated **"MDM Bridge Configuration"** section that shows:

1. **MDM Framework Status** — Are the base enum types loaded? (`DataManagerLog`, `DataManagerContentType`)
2. **Fix MDM Data** dialog — If base data is missing, shows the XML to load and a button to load it
3. **DataManagerConfig list** — Are `SYNC_SHOPIFY_ORDER` and `BULK_ORDER_HISTORY` configured?
4. **Job status** — Is `consume_ShopifyOrders_SQS` job active and configured?

This is the **single pane of glass** for diagnosing order import issues.

---

## 6. MDM in the Shopify Order Import Flow

This is the most critical use case. Here is the complete end-to-end flow:

```
Shopify (Merchant Store)
        │
        │ Order created / updated webhook
        ▼
AWS SQS Queue (per shop)
        │
        │ Polled every N seconds by scheduled job
        ▼
[MAARG Job: consume_ShopifyOrders_SQS]
  Service: co.hotwax.shopify.order.SqsOrderImport.consume#SQSOrderMessages
        │
        │ Reads messages in batches of 10
        │ Extracts orderId + shopDomain
        │ Resolves SystemMessageRemote for shop
        ▼
[Service: stage#ShopifyOrder]
  Service: co.hotwax.shopify.order.SqsOrderImport.stage#ShopifyOrder
        │
        │ For each orderId:
        │   → calls get#ShopifyOrderDetails (GraphQL to Shopify)
        │   → writes all order details to a JSON array in memory/disk
        │   → saves to: runtime://datamanager/orders/raw/{UUID}.json
        ▼
[MDM Upload]
  Service: co.hotwax.util.UtilityServices.upload#DataManagerFile
  Parameters: configId='SYNC_SHOPIFY_ORDER', contentFile=fileItem, parameters=[shopId:...]
        │
        │ Creates DataManagerLog (status=PENDING)
        │ Creates DataManagerContent (type=DmcntImported)
        │ Puts log into MDM Priority Worker Pool queue
        ▼
[MDM Runner picks up log from queue]
  Status: PENDING → QUEUED → RUNNING
        │
        │ Reads importServiceName from DataManagerConfig
        │ configId='SYNC_SHOPIFY_ORDER'
        │ importServiceName='co.hotwax.sob.order.ShopifyOrderServices.sync#ShopifyOrder'
        ▼
[Service: sync#ShopifyOrder]
  Component: shopify-oms-bridge
        │
        │ Reads JSON file
        │ Iterates each order in the array
        │ For each order:
        │   → map#ShopifyOrder (ShopifyOrderMappingServices)
        │   → Resolves product via GoodIdentification (SKU/ShopifyProductId)
        │   → Resolves facility via ShopifyShopLocation
        │   → create/update OrderHeader in OFBiz-OMS
        │   → create OrderItems, OrderRole, OrderContactMech
        │   → create OrderPaymentPreference
        │   → trigger order approval flow
        ▼
Status: RUNNING → FINISHED (or FAILED)
DataManagerLog updated with result
Error records → DataManagerContent (DmcntError)
```

---

## 7. The Two Shopify-Specific DataManagerConfig IDs

### `SYNC_SHOPIFY_ORDER`
```xml
<co.hotwax.datamanager.DataManagerConfig
    configId="SYNC_SHOPIFY_ORDER"
    importServiceName="co.hotwax.sob.order.ShopifyOrderServices.sync#ShopifyOrder"
    description="Handles Shopify orders, refunds, exchanges, cancellations, and updates"
    enableDataFeed="Y"/>
```
- Primary real-time order import config
- `enableDataFeed="Y"` means after import, a DataFeed event fires (used for downstream webhooks/notifications)
- Used by both the new SQS-based flow (mantle-shopify-connector) and the legacy webhook flow

### `BULK_ORDER_HISTORY`
```xml
<co.hotwax.datamanager.DataManagerConfig
    configId="BULK_ORDER_HISTORY"
    importServiceName="co.hotwax.sob.order.ShopifyOrderSyncHistoryServices.create#ShopifyOrderSyncHistory"
    description="Processes bulk order history records from Shopify JSONL migration"/>
```
- Used during **initial onboarding / migration**
- Processes JSONL files from Shopify's bulk export API
- Streams records to `runtime://datamanager/orders/raw/` then uploads to MDM

---

## 8. Why MDM is Critical for Shopify Order Import

| Without MDM | With MDM |
|---|---|
| Shopify webhook hits OMS directly — any failure loses the order | MDM stages to disk/DB first — data is safe even if processing fails |
| No retry mechanism | Failed logs can be re-queued or re-run manually |
| No visibility into what's processing | Full log history with status, file links, error records |
| All orders compete for the same thread pool | Priority pool ensures orders aren't starved by bulk jobs |
| No audit trail | Every file, every run, every error is logged with timestamps |
| Scale issues — Shopify bursts can overwhelm | Queue absorbs bursts; pool processes at controlled rate |

---

## 9. Full Catalog of DataManagerConfig IDs (in ofbiz-oms-udm)

### Product & Catalog
| configId | importServiceName | Notes |
|---|---|---|
| `MDM_PRODUCT` | `productsDataSetup` | Main product import |
| `MDM_CATEGORY` | `catalogCategoryDataSetup` | Category hierarchy |
| `MDM_PRODUCT_ASSOC` | `productAssocDataSetup` | Parent-variant associations |
| `MDM_PRODUCT_PRICE` | `productPriceDataSetup` | Pricing |
| `MDM_PROD_FETR` | `importProductFeatures` | Features (color, size) |
| `MDM_PROD_TEXT_CNTNT` | `productTextContentDataSetup` | Long description, SEO |
| `MDM_CATEGORY_CNTNT` | `catalogCategoryContentDataSetup` | Category banners etc |
| `MDM_PROD_CAT_MEMBER` | `importProductCategroyMember` | Category membership |
| `MDM_PRODUCT_PROMO` | `importProductPromo` | Promotions |
| `MDM_CRT_CNFG_PRDCT` | `createConfigurableProduct` | Create configurable skeleton |
| `MDM_CNFG_CNFG_PRDCT` | `configureConfigurableProduct` | Assign variants to configurable |
| `MDM_PRODUCT_LONGDESC` | `productsDataSetup` | Products missing long desc |
| `MDM_PRODUCT_MISS_IMG` | `productsDataSetup` | Products missing main image |
| `FIND_PROD_TEXT_CNTNT` | `importProductTextContent` | Text content direct import |

### Inventory
| configId | Notes |
|---|---|
| `MDM_RECEIVE_INV` | Bulk inventory receive |
| `MDM_INV_VARIANCE` | Record variance / adjust inventory |
| `MDM_PROD_FAC_LOC` | Product facility locations |
| `MDM_FACILITY_LOC` | Facility location setup |
| `AVG_INV_COST_FEED` | Average inventory cost |
| `AVG_INV_LND_CST_FEED` | Average landed cost |

### Orders
| configId | importServiceName | Notes |
|---|---|
| `SYNC_SHOPIFY_ORDER` | `sync#ShopifyOrder` | **Shopify order real-time import** |
| `BULK_ORDER_HISTORY` | `create#ShopifyOrderSyncHistory` | Shopify migration JSONL |
| `IMP_APR_SALES_ORD` | `approveSalesOrder` | Approve orders from file |
| `IMP_ODR_ITM_FLFLMNT` | `processOrderCompleteRequest` | Complete order items |
| `MDM_UPD_ORD_FMNT_HST` | `createUpdateOrderFulfillmentHistory` | Fulfillment history |
| `MDM_RST_FULFD_ORD` | `refreshExportedFulfillment` | Reset for re-fulfillment |
| `IMP_ORDER_IDENT` | `createUpdateOrderIdentification` | Order identification |
| `IMP_ORDER_ITM_ATTR` | `createUpdateOrderItemAttribute` | Order item attributes |
| `IMP_ORD_ITEM_UPD` | (via importPath) | Order item update |
| `IMP_CRT_RTN_ORD` | `createShopifyReturn` | Create return orders |
| `IMP_CRT_EXCHG_ORD` | `createSalesOrder` | Create exchange orders |

### Party / Customer
| configId | importServiceName |
|---|---|
| `MDM_PARTY_PROFILE` | `partyProfileDataSetup` |
| `MDM_PRTY_SHP_TO_ADD` | `createNewPartyShipToAddress` |
| `IMP_PARTY_IDENT` | `createUpdatePartyIdentification` |

### Supplier & Agreements
| configId | importServiceName |
|---|---|
| `MDM_SUPPLIER_PROD` | `uploadSupplierProducts` |
| `MDM_PROD_AGRMNT` | `importProductAgreements` |

### Content / Media
| configId | importServiceName |
|---|---|
| `MDM_CNTNT_META_DATA` | `importContentMetaData` |
| `IMPO_PRD_CODE` | `createUpdateProductErpId` |

### Shipment
| configId | importServiceName |
|---|---|
| `IMP_INCOMING_SHPMNT` | `createIncomingShipment` |

### Generic
| configId | importServiceName |
|---|---|
| `IMP_JSON_DATA` | `importJsonData` — generic JSON |
| `IMP_JSON_LIST_DATA` | `importJsonListData` — generic JSON array |

---

## 10. Backend: How MDM Processes a File (step-by-step)

```
1. upload#DataManagerFile is called
   Input: configId, contentFile (DiskFileItem), parameters (List<Map.Entry>)

2. MDM framework:
   a. Generates logId (sequence)
   b. Saves file to runtime://datamanager/<path>/
   c. Creates DataManagerLog { statusId: DmlsPending, logTypeEnumId: DmltImport }
   d. Creates DataManagerContent { logContentTypeEnumId: DmcntImported }
   e. Stores extra params in DataManagerParameter
   f. Pushes logId to Priority or Normal pool queue

3. ScheduledDataManagerRunner picks up logId from queue
   a. Updates log → DmlsQueued
   b. Acquires thread from pool
   c. Updates log → DmlsRunning
   d. Reads importServiceName from DataManagerConfig
   e. Builds service call: importServiceName + file content + DataManagerParameter values
   f. Executes service call synchronously in this thread

4. Service executes (e.g. sync#ShopifyOrder)
   a. Reads file (JSON/CSV/JSONL)
   b. Processes each record
   c. Tracks errors in an error accumulator
   d. Returns success/failure

5. MDM framework post-processing:
   a. If success → status = DmlsFinished
   b. If errors → writes error file, creates DataManagerContent (DmcntError)
   c. If exception → status = DmlsCrashed
   d. Writes execution log → DataManagerContent (DmcntLog)
   e. If notifyOnFailure=Y and failed → sends alert notification
```

---

## 11. MDM's Role in Product Identification (GoodIdentification)

Before MDM can create an `OrderItem`, it must resolve Shopify's product identifiers to OFBiz internal `productId`. This uses the `GoodIdentification` entity:

```
GoodIdentification
├── goodIdentificationTypeId (PK) → e.g. SHOPIFY_PROD_ID, SHOPIFY_PROD_SKU, SKU, ERP_ID
├── productId (PK) → internal OFBiz product ID
├── idValue (PK) → the external identifier value
├── fromDate / thruDate → validity window
```

**Seed data types** (from `ShopifySeedData.xml`):
| goodIdentificationTypeId | parentTypeId | Description |
|---|---|---|
| `SHOPIFY_PROD_SKU` | `HC_GOOD_ID_TYPE` | Shopify SKU |
| `SHOPIFY_PROD_ID` | `HC_GOOD_ID_TYPE` | Shopify Product (variant) ID |
| `ERP_ID` | `HC_GOOD_ID_TYPE` | ERP system ID |
| `SKU` | (standard) | Internal SKU |

**During order import**, `sync#ShopifyOrder` uses `ShopifyProductId` or `SKU` from the Shopify line item to look up `GoodIdentification` and find the OFBiz `productId`. If no match → order item fails (logged to error file via MDM).

---

## 12. The `enableDataFeed` Flag

When `DataManagerConfig.enableDataFeed = Y` (as on `SYNC_SHOPIFY_ORDER`), after the import service completes successfully, MDM fires a **DataFeed** event. This is Moqui's pub/sub mechanism — other components can subscribe to receive notifications when Shopify orders are imported. This drives:
- Real-time inventory reservation triggers
- Order routing job triggers
- Notification services

---

## 13. Health Checks (ShopifyOrderIntegrationSetupServices)

The setup service `check#ShopifyOrderIntegrationHealth` validates:

1. **MDM Framework Loaded**: `DataManagerLog` EnumerationType + `DataManagerContentType` EnumerationType exist
2. **DataManagerConfig records exist**: `SYNC_SHOPIFY_ORDER`, `BULK_ORDER_HISTORY` both present
3. **ServiceJob active**: `consume_ShopifyOrders_SQS` job exists, not paused, has `queueName` + `systemMessageRemoteId` params
4. **SQS connectivity**: Can the AWS SQS tool authenticate?
5. **Shop mapping**: `SystemMessageRemote` for the shop is configured with correct scope

If any check fails → the Setup UI shows a red badge and a "Fix" action (load missing XML data, configure job, etc.)

---

## 14. Summary: Why Everything Depends on MDM

```
Shopify ──► SQS ──► [MDM] ──► OFBiz-OMS
                        │
              ┌─────────┼──────────┐
         File stored  Log created  Workers process
         on disk     in DB        via import service
              │
         If fails → Error file tracked
         If success → DataFeed fires
                           │
                    Inventory reserved
                    Order routed
                    Fulfillment triggered
```

MDM is **not optional**. Every Shopify order that enters OMS goes through a `DataManagerLog` record. The MDM worker pools are the only execution context for order processing. Without MDM:
- No orders can be imported
- No bulk data (products, inventory) can be loaded
- No audit trail of what succeeded/failed
- No retry capability for failed imports

The **two thread pools** ensure order import (Priority) is never starved by a simultaneous bulk product upload (Normal).
