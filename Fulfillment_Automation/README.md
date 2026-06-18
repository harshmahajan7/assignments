# OMS Fulfillment Lifecycle Automation

Automates the complete **Pick → Pack → Ship** fulfillment lifecycle using the OMS (HotWax Commerce) API — no UI interaction required.

## Overview

```
0.1 Login
 └─ sets: api_token
1.1 Find Open Order       (Solr query)
 └─ sets: order_id, order_item_seq_id, ship_group_seq_id, product_id
1.2 Create Picklist       (Pick)
 └─ sets: picklist_id, shipment_id
2.1 Get Shipment Details  (assert SHIPMENT_APPROVED)
2.2 Pack Shipment         (SHIPMENT_APPROVED → SHIPMENT_PACKED)
3.1 Get Packed Shipment   (assert SHIPMENT_PACKED)
3.2 Ship Shipment         (SHIPMENT_PACKED → SHIPMENT_SHIPPED)
4.1 Verify Shipment       (assert SHIPMENT_SHIPPED)
4.2 Verify Order Items    (assert ITEM_COMPLETED)
```

## Files

| File | Description |
|------|-------------|
| `OMS_Fulfillment_Lifecycle_Collection.json` | Postman Collection v2.1.0 with all 8 requests and automation scripts |
| `OMS_Fulfillment_Dev_Environment.json` | Postman Environment with all configurable & auto-set variables |

## Setup

1. **Import** both files into Postman (File → Import).
2. **Select** the `OMS Fulfillment - Dev` environment from the top-right dropdown.
3. **Configure** these variables in the environment (pre-filled with defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `base_url` | `https://nextgen-oms.hotwax.io` | OMS instance URL (no trailing slash) |
| `username` | `hotwax.user` | OMS login username |
| `password` | `hotwax@123` | OMS login password (secret) |
| `facility_id` | `DEMO_FACILITY` | Fulfillment facility ID |
| `product_store_id` | `STORE` | Product store ID |
| `picker_party_id` | `_NA_` | Picker's partyId |
| `carrier_party_id` | `_NA_` | Carrier party ID |
| `shipment_method_type_id` | `STANDARD` | Shipping method |
| `shipment_box_type_id` | `YOURPACKNG` | Box type for packing |
| `tracking_code` | `TRACK123456` | Carrier tracking number |

## Running the Collection

### Option A: Collection Runner (Full Automation)
1. Click **Run collection** in Postman.
2. Select `OMS Fulfillment - Dev` environment.
3. Click **Run OMS Fulfillment Lifecycle**.
4. All 8 requests execute in sequence with variables chained automatically.

### Option B: Individual Requests
Run each request manually in order (0.1 → 1.1 → 1.2 → 2.1 → 2.2 → 3.1 → 3.2 → 4.1 → 4.2).

## Variable Chaining (Data Flow)

Variables are automatically passed between requests using `pm.environment.set()` in test scripts:

```
Login ──────────────────────────→ api_token
Find Open Order ────────────────→ order_id, order_item_seq_id,
                                   ship_group_seq_id, product_id
Create Picklist (Pick) ─────────→ picklist_id, shipment_id
Pack Shipment ──────────────────→ (uses shipment_id)
Ship Shipment ──────────────────→ (uses shipment_id)
```

## Guard Rails

Each request includes a **pre-request script** that throws an error and halts execution if required variables are missing. This prevents partial or invalid API calls.

## Postman Links

- **Collection**: [OMS Fulfillment Lifecycle - Pick → Pack → Ship](https://go.postman.co/workspace/My-Workspace~a032a408-2e60-4ea0-8b9b-aca9ade00aa1/collection/30768967-0367c985-f4d0-494b-9fa4-c4ade2d8d367)
- **Environment**: [OMS Fulfillment - Dev](https://go.postman.co/workspace/My-Workspace~a032a408-2e60-4ea0-8b9b-aca9ade00aa1/environment/30768967-4a2a0448-8fd4-4226-ac26-b9cca3a4ddb8)
