# SQL Queries Documentation (Updated)

## 8. Orders Without Shipment / Payment Issue

``` sql
SELECT
    oh.order_id,
    oh.STATUS_ID,
    opp.STATUS_ID AS Payment_Status,
    s.STATUS_ID AS SHIPPING_Status

FROM order_header oh

LEFT JOIN order_payment_preference opp
ON oh.order_id = opp.order_id

LEFT JOIN shipment s
ON oh.ORDER_id = s.PRIMARY_ORDER_ID

WHERE 
(opp.status_id = 'PAYMENT_SETTLED'
OR opp.status_id = 'Payment_Received')
AND
(s.status_id != 'SHIPMENT_SHIPPED'
OR s.status_id IS NULL);
```

------------------------------------------------------------------------

## 10. Store Pickup Orders Revenue (Last 1 Year)

``` sql
SELECT 
COUNT(DISTINCT oh.ORDER_ID) AS total_orders,

SUM(
    CASE
    WHEN oisg.shipment_method_type_id = 'STOREPICKUP'
    THEN oi.quantity * oi.unit_price
    ELSE 0
    END
) AS total_revenue

FROM order_header oh

JOIN order_item oi
ON oh.order_id = oi.order_id

JOIN order_item_ship_group oisg
ON oi.order_id = oisg.order_id
AND oi.ship_group_seq_id = oisg.ship_group_seq_id

WHERE oh.order_date >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
AND oisg.shipment_method_type_id = 'STOREPICKUP';
```

------------------------------------------------------------------------

## 11. Cancelled Orders Reason Analysis

``` sql
SELECT
COUNT(DISTINCT oh.order_id) AS total_orders,
os.change_reason AS cancellation_reason

FROM order_header oh

JOIN order_status os
ON oh.order_id = os.order_id

WHERE oh.status_id = 'ORDER_CANCELLED'

GROUP BY os.change_reason;
```

------------------------------------------------------------------------

## 12. Product Minimum Stock Threshold

``` sql
SELECT 
product_id,
minimum_stock AS threshold

FROM product_facility;
```

------------------------------------------------------------------------

# Previously Added Queries

The above queries should be appended with the previously created
SQL_Queries_Documentation.md file.
