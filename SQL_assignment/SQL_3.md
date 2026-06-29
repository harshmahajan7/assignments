# SQL Queries Documentation

---

# 1. Completed Sales Orders (Physical Items)

## Business Problem
Merchants need to track only physical items requiring shipping and fulfillment for logistics and shipping-cost analysis.

## Fields
- ORDER_ID
- ORDER_ITEM_SEQ_ID
- PRODUCT_ID
- PRODUCT_TYPE_ID
- SALES_CHANNEL_ENUM_ID
- ORDER_DATE
- ENTRY_DATE
- STATUS_ID
- STATUS_DATETIME
- ORDER_TYPE_ID
- PRODUCT_STORE_ID

## SQL Query

```sql
SELECT
    oi.ORDER_ID,
    oi.ORDER_ITEM_SEQ_ID,
    oi.PRODUCT_ID,
    p.PRODUCT_TYPE_ID,
    oh.SALES_CHANNEL_ENUM_ID,
    oh.ORDER_DATE,
    oh.ENTRY_DATE,
    oh.STATUS_ID,
    os.STATUS_DATETIME,
    oh.ORDER_TYPE_ID,
    oh.PRODUCT_STORE_ID

FROM order_item oi

JOIN product p
ON oi.PRODUCT_ID = p.PRODUCT_ID

JOIN order_status os
ON oi.ORDER_ID = os.ORDER_ID

JOIN order_header oh
ON oi.ORDER_ID = oh.ORDER_ID

JOIN product_type pt
ON p.PRODUCT_TYPE_ID = pt.PRODUCT_TYPE_ID

WHERE pt.IS_PHYSICAL='Y'
AND oh.STATUS_ID='ORDER_COMPLETED'
AND oh.ORDER_TYPE_ID='SALES_ORDER';
```

---

# 2. Completed Return Items

## Business Problem
Customer service and finance need return details for refunds, replacements and restocking.

## Fields
- RETURN_ID
- ORDER_ID
- PRODUCT_STORE_ID
- STATUS_DATETIME
- ORDER_NAME
- FROM_PARTY_ID
- RETURN_DATE
- ENTRY_DATE
- RETURN_CHANNEL_ENUM_ID

## SQL Query

```sql
SELECT

rh.return_id,
ri.order_id,
oh.product_store_id,
rs.status_datetime,
oh.order_name,
rh.from_party_id,
rh.return_date,
rh.entry_date,
rh.return_channel_enum_id

FROM return_header rh

JOIN return_item ri
ON rh.return_id = ri.return_id

JOIN return_status rs
ON rh.return_id = rs.return_id

JOIN order_header oh
ON ri.order_id = oh.order_id

WHERE rh.return_header_type_id='CUSTOMER_RETURN'
AND rh.status_id='RETURN_COMPLETED';
```

---

# 3. Single Return Orders

## Business Problem
Find customers having only one return.

## Fields
- PARTY_ID
- FIRST_NAME

## SQL Query

```sql
SELECT

p.party_id,
p.first_name

FROM person p

JOIN return_header rh

ON p.party_id = rh.from_party_id

GROUP BY
p.party_id,
p.first_name

HAVING COUNT(DISTINCT rh.return_id)=1;
```

---

# 4. Returns and Appeasements

## Business Problem
Calculate returned amount and appeasement amount.

## SQL Query

```sql
SELECT

SUM(ri.RETURN_QUANTITY * ri.RETURN_PRICE) 
AS TOTAL_RETURN_AMOUNT,

COUNT(DISTINCT ri.RETURN_ID)
AS TOTAL_RETURNS,


SUM(ra.AMOUNT)
AS TOTAL_APPEASEMENTS_AMOUNT,


COUNT(DISTINCT ra.RETURN_ADJUSTMENT_ID)
AS TOTAL_APPEASEMENTS


FROM return_header rh


JOIN return_item ri
ON rh.RETURN_ID = ri.RETURN_ID


JOIN return_adjustment ra
ON rh.RETURN_ID = ra.RETURN_ID


WHERE RETURN_ADJUSTMENT_TYPE_ID='APPEASEMENTS';
```

---

# 5. Detailed Return Information

## Fields
- RETURN_ID
- ENTRY_DATE
- RETURN_ADJUSTMENT_TYPE_ID
- AMOUNT
- COMMENTS
- ORDER_ID
- ORDER_DATE
- RETURN_DATE
- PRODUCT_STORE_ID


## SQL Query

```sql
SELECT

rh.RETURN_ID,
rh.ENTRY_DATE,
ra.RETURN_ADJUSTMENT_TYPE_ID,
ra.AMOUNT,
ra.COMMENTS,
ri.ORDER_ID,
oh.ORDER_DATE,
rh.RETURN_DATE,
oh.PRODUCT_STORE_ID


FROM return_header rh


JOIN return_item ri
ON rh.RETURN_ID = ri.RETURN_ID


JOIN return_adjustment ra
ON ri.RETURN_ITEM_SEQ_ID = ra.RETURN_ITEM_SEQ_ID
AND ri.RETURN_ID = ra.RETURN_ID


JOIN order_header oh
ON ri.ORDER_ID = oh.ORDER_ID;
```

---

# 6. Orders with Multiple Returns

```sql
SELECT

ri.ORDER_ID,
ri.RETURN_ID,
rh.RETURN_DATE,
ri.RETURN_REASON_ID AS RETURN_REASON,
ri.RETURN_QUANTITY


FROM return_header rh


JOIN return_item ri

ON rh.RETURN_ID = ri.RETURN_ID


WHERE ri.ORDER_ID IN

(
SELECT ORDER_ID

FROM return_item

GROUP BY ORDER_ID

HAVING COUNT(ORDER_ID)>1
);
```

---

# 7. Store with Most One-Day Shipped Orders

```sql
SELECT

f.facility_id,

f.facility_name,


COUNT(DISTINCT oh.order_id)
AS total_one_day_ship_orders,


DATE_FORMAT(
DATE_SUB(CURDATE(),INTERVAL 1 MONTH),
'%Y-%m'
)

AS reporting_period


FROM facility f


JOIN shipment s

ON f.facility_id=s.origin_facility_id


JOIN order_header oh

ON s.primary_order_id=oh.order_id


GROUP BY

f.facility_id,
f.facility_name


ORDER BY total_one_day_ship_orders DESC


LIMIT 1;
```

---

# 8. Orders Payment Completed But Not Shipped

```sql
SELECT

oh.order_id,

oh.STATUS_ID,

opp.STATUS_ID AS Payment_Status,

s.STATUS_ID AS SHIPPING_Status


FROM order_header oh


LEFT JOIN order_payment_preference opp

ON oh.order_id = opp.order_id


LEFT JOIN shipment s

ON oh.ORDER_id=s.PRIMARY_ORDER_ID


WHERE

(
opp.status_id='PAYMENT_SETTLED'

OR

opp.status_id='Payment_Received'
)

AND

(
s.status_id!='SHIPMENT_SHIPPED'

OR

s.status_id IS NULL
);
```

---

# 9. Total Facilities Selling Product

## Fields
- PRODUCT_ID
- PRODUCT_NAME
- FACILITY_COUNT
- FACILITY_ID LIST

---

# 10. Store Pickup Orders Revenue (Last Year)

```sql
SELECT

COUNT(DISTINCT oh.ORDER_ID)
AS total_orders,


SUM(

CASE

WHEN oisg.shipment_method_type_id='STOREPICKUP'

THEN oi.quantity * oi.unit_price

ELSE 0

END

)

AS total_revenue


FROM order_header oh


JOIN order_item oi

ON oh.order_id=oi.order_id


JOIN order_item_ship_group oisg

ON oi.order_id=oisg.order_id

AND oi.ship_group_seq_id=oisg.ship_group_seq_id


WHERE oh.order_date >= DATE_SUB(NOW(),INTERVAL 1 YEAR)


AND oisg.shipment_method_type_id='STOREPICKUP';
```

---

# 11. Cancelled Orders Reason Analysis

```sql
SELECT

COUNT(DISTINCT oh.order_id)
AS total_orders,


os.change_reason
AS cancellation_reason


FROM order_header oh


JOIN order_status os

ON oh.order_id=os.order_id


WHERE oh.status_id='ORDER_CANCELLED'


GROUP BY os.change_reason;
```

---

# 12. Product Minimum Stock Threshold

```sql
SELECT

product_id,

minimum_stock AS threshold


FROM product_facility;
```
