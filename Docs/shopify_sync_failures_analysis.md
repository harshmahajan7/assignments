# Shopify-OMS Synchronization Audit & Analysis

This document outlines the investigation, resolution, and audit query construction for transactional `XAER_RMFAIL` rollback failures within the Shopify-to-OMS synchronization pipeline.

---

## 1. Transaction Rollback (`XAER_RMFAIL`) Resolution

### Root Cause Analysis
During synchronization, lookups of `ShopifyShopOrder` records were executed within the `getShopifyOrderItems` service. Because OFBiz services default to running inside active transactions (`use-transaction="true"`), the query attempted to enlist a connection proxy (`ConnectionJavaProxy`) into the active global JTA transaction. 

When a prior service in the pipeline failed or marked the transaction as rollback-only, subsequent read-only lookups on `ShopifyShopOrder` failed with:
`java.sql.SQLException: error enlisting a ConnectionJavaProxy of a JdbcPooledConnection...`

### Resolution
The `getShopifyOrderItems` service is a read-only helper service that retrieves order items. It does not perform database writes and should not run in a transaction context. By setting `use-transaction="false"`, we allow the query to execute outside transaction boundaries, preventing connection proxy enlistment errors and isolating order item lookups from pipeline failures.

#### Implementation Diff
[services.xml](file:///home/harshmahajan/Sandbox/ofbiz-oms/applications/shopify-connector/servicedef/services.xml#L1038-1045)
```diff
     <service name="getShopifyOrderItems" engine="java"
-             location="co.hotwax.shopify.ShopifyHelperServices" invoke="getShopifyOrderItems" auth="true">
+             location="co.hotwax.shopify.ShopifyHelperServices" invoke="getShopifyOrderItems" auth="true" use-transaction="false">
         <description>Get OMS order items for shopify order/item</description>
```

---

## 2. Audit Trail Reconstruction Query

To link external Shopify order identifiers with the ingestion logs and system message events, the following SQL join query connects `DataManagerLog`, `OrderSystemMessage`, and `ShopifyShopOrder`.

### SQL Query
```sql
SELECT 
    dml.LOG_ID AS artifact_log_id,
    dml.SYSTEM_MESSAGE_ID AS artifact_event_id,
    sso.SHOPIFY_ORDER_ID AS shopify_id
FROM data_manager_log dml
JOIN order_system_message osm ON dml.SYSTEM_MESSAGE_ID = osm.SYSTEM_MESSAGE_ID
JOIN shopify_shop_order sso ON osm.ORDER_ID = sso.ORDER_ID;
```

### Key Mapping Associations
- **`data_manager_log` (dml)**: Contains the execution audit trail, tracking `LOG_ID` (the logical `artifact_log_id`) and the associated `SYSTEM_MESSAGE_ID`.
- **`order_system_message` (osm)**: Serves as the junction table mapping the successful processing of a `SYSTEM_MESSAGE_ID` (the logical `artifact_event_id`) to the generated internal `ORDER_ID`.
- **`shopify_shop_order` (sso)**: Maps the internal `ORDER_ID` to the external `SHOPIFY_ORDER_ID` (the logical `shopify_id`).

---

## 3. Moqui Ingestion Mappings & Event Logging Verification

In the Moqui framework, the integration flow is tracked and logged through the following stages:

1. **Job Execution Tracking**: 
   Background ingestion jobs are run via the `ScheduledDataManagerRunner` and `DataManagerToolFactory` components. Each execution context reads `_jobRunId` to associate the service run with a specific `DataManagerLog` record.
2. **System Message Logs**: 
   When a Shopify sync event occurs, a `SystemMessage` record of type `ShopifyOrderSync` is initialized. The message contains configuration payloads or actual order details.
3. **Internal Order Linkage**: 
   When the order is successfully ingested and saved as an `OrderHeader` record in the OMS, the bridge table `order_system_message` is populated with `ORDER_ID` and the corresponding `SYSTEM_MESSAGE_ID`. This links the ingestion event (`system_message.SYSTEM_MESSAGE_ID`) directly to the created internal order, enabling complete end-to-end audit tracking.
