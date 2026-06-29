# SQL Queries Documentation

## 1. Completed Sales Orders (Physical Items)

### Business Problem
Merchants need to track only physical items (requiring shipping and fulfillment) for logistics and shipping-cost analysis.

### Fields to Retrieve
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

### SQL Query

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

WHERE pt.IS_PHYSICAL = 'Y'
AND oh.STATUS_ID = 'ORDER_COMPLETED'
AND oh.ORDER_TYPE_ID = 'SALES_ORDER';
```

---

# 2. Completed Return Items

## Business Problem
Customer service and finance need return insights for refunds, replacements, and inventory restocking.

## Fields to Retrieve
- RETURN_ID
- ORDER_ID
- PRODUCT_STORE_ID
- STATUS_DATETIME
- ORDER_NAME
- FROM_PARTY_ID
- RETURN_DATE
- ENTRY_DATE
- RETURN_CHANNEL_ENUM_ID

### SQL Query

```sql
SELECT
    rh.RETURN_ID,
    ri.ORDER_ID,
    oh.PRODUCT_STORE_ID,
    rs.STATUS_DATETIME,
    oh.ORDER_NAME,
    rh.FROM_PARTY_ID,
    rh.RETURN_DATE,
    rh.ENTRY_DATE,
    rh.RETURN_CHANNEL_ENUM_ID

FROM return_header rh

JOIN return_item ri
ON rh.RETURN_ID = ri.RETURN_ID

JOIN return_status rs
ON rh.RETURN_ID = rs.RETURN_ID

JOIN order_header oh
ON ri.ORDER_ID = oh.ORDER_ID

WHERE rh.RETURN_HEADER_TYPE_ID='CUSTOMER_RETURN'
AND rh.STATUS_ID='RETURN_COMPLETED';
```

---

# 3. Single-Return Orders

## Business Problem
Find customers/orders having only one return.

### Fields
- PARTY_ID
- FIRST_NAME

### SQL Query

```sql
SELECT
    p.PARTY_ID,
    p.FIRST_NAME

FROM person p

JOIN return_header rh
ON p.PARTY_ID = rh.FROM_PARTY_ID

GROUP BY
    p.PARTY_ID,
    p.FIRST_NAME

HAVING COUNT(DISTINCT rh.RETURN_ID)=1;
```

---

# 4. Returns and Appeasements

## Business Problem
Find total returned amount and appeasement amount.

### SQL Query

```sql
SELECT

SUM(ri.RETURN_QUANTITY * ri.RETURN_PRICE) AS TOTAL_RETURN_AMOUNT,

COUNT(DISTINCT ri.RETURN_ID) AS TOTAL_RETURNS,

SUM(ra.AMOUNT) AS TOTAL_APPEASEMENTS_AMOUNT,

COUNT(DISTINCT ra.RETURN_ADJUSTMENT_ID) AS TOTAL_APPEASEMENTS

FROM return_header rh

JOIN return_item ri
ON rh.RETURN_ID = ri.RETURN_ID

JOIN return_adjustment ra
ON rh.RETURN_ID = ra.RETURN_ID

WHERE RETURN_ADJUSTMENT_TYPE_ID='APPEASEMENTS';
```

---

# 5. Detailed Return Information

### Fields
- RETURN_ID
- ENTRY_DATE
- RETURN_ADJUSTMENT_TYPE_ID
- AMOUNT
- COMMENTS
- ORDER_ID
- ORDER_DATE
- RETURN_DATE
- PRODUCT_STORE_ID

### SQL Query

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

f.FACILITY_ID,
f.FACILITY_NAME,

COUNT(DISTINCT oh.ORDER_ID) AS TOTAL_ONE_DAY_SHIP_ORDERS,

DATE_FORMAT(
DATE_SUB(CURDATE(),INTERVAL 1 MONTH),
'%Y-%m'
) AS REPORTING_PERIOD

FROM facility f

JOIN shipment s
ON f.FACILITY_ID=s.ORIGIN_FACILITY_ID

JOIN order_header oh
ON s.PRIMARY_ORDER_ID=oh.ORDER_ID

GROUP BY
f.FACILITY_ID,
f.FACILITY_NAME

ORDER BY TOTAL_ONE_DAY_SHIP_ORDERS DESC

LIMIT 1;
```

---

# 8. List of Warehouse Pickers

## Fields
- PARTY_ID
- NAME
- ROLE_TYPE_ID
- FACILITY_ID
- STATUS


---

# 9. Total Facilities That Sell the Product

## Fields
- PRODUCT_ID
- PRODUCT_NAME
- FACILITY_COUNT
- FACILITY_ID LIST


---

# 10. Inventory in Facilities

```sql
SELECT

pf.PRODUCT_ID,
pf.FACILITY_ID,
f.FACILITY_TYPE_ID,

ii.QUANTITY_ON_HAND_TOTAL AS QOH,

ii.AVAILABLE_TO_PROMISE_TOTAL AS ATP

FROM product_facility pf

JOIN facility f
ON pf.FACILITY_ID=f.FACILITY_ID

JOIN inventory_item ii

ON pf.PRODUCT_ID=ii.PRODUCT_ID
AND pf.FACILITY_ID=ii.FACILITY_ID;
```

---

# 11. Transfer Orders Without Inventory Reservation

## Fields
- TRANSFER_ORDER_ID
- FROM_FACILITY_ID
- TO_FACILITY_ID
- PRODUCT_ID
- REQUESTED_QUANTITY
- RESERVED_QUANTITY
- TRANSFER_DATE
- STATUS


---

# 12. Orders Without Picklist

## Fields
- ORDER_ID
- ORDER_DATE
- ORDER_STATUS
- FACILITY_ID
- DURATION
