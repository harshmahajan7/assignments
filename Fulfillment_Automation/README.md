# Fulfillment Automation — Pick → Pack → Ship

This folder contains a Postman collection that automates the complete OMS order fulfillment lifecycle **without using the application UI**.

## Flow

```
auth  →  pick (createOrderFulfillmentWave)  →  pack  →  ship
```

| Step | Request | Method | Endpoint |
|------|---------|--------|----------|
| 1 | **auth** | POST | `https://nextgen-oms.hotwax.io/api/login` |
| 2 | **pick** | POST | `https://nextgen-maarg.hotwax.io/rest/s1/poorti/createOrderFulfillmentWave` |
| 3 | **pack** | POST | `https://nextgen-maarg.hotwax.io/rest/s1/poorti/shipments/{shipmentId}/pack` |
| 4 | **ship** | POST | `https://nextgen-maarg.hotwax.io/rest/s1/poorti/shipments/{shipmentId}/ship` |

## Files

| File | Description |
|------|-------------|
| `pick_pack_ship.json` | Postman collection (import into Postman) |

## How to Use

1. **Import** `pick_pack_ship.json` into Postman.
2. Set collection variables:
   - `username` — your OMS username (e.g., `hotwax.user`)
   - `password` — your OMS password (**never hardcode in the file**)
3. Run **auth** first — the test script auto-saves the token to `auth_secret_0s0e`.
4. Run **pick** — creates a fulfillment wave; test script saves `shipment_id`.
5. Run **pack** — packs the shipment.
6. Run **ship** — marks shipment as `SHIPMENT_SHIPPED`.

## Key Parameters (in pick request body)

```json
{
  "facilityId": "MAPLEWOOD",
  "shipmentMethodTypeId": "STANDARD",
  "orderItems": [
    {
      "orderId": "M102719",
      "orderItemSeqId": "02",
      "shipGroupSeqId": "00006",
      "productId": "M103006",
      "quantity": 1
    }
  ]
}
```

> **Note:** Update `orderId`, `orderItemSeqId`, `shipGroupSeqId`, and `shipmentId` with real values from your OMS instance before running.

## Status Lifecycle

```
ITEM_APPROVED
  └─[pick]──► SHIPMENT_APPROVED
                  └─[pack]──► SHIPMENT_PACKED
                                  └─[ship]──► SHIPMENT_SHIPPED ✅
                                                  └──► ITEM_COMPLETED
```
