https://docs.google.com/document/d/1NbIJYdcJmaPYZnR8O8N_JQW9b_7mJpzhlCSIDO5tL90/edit?usp=sharing

1 Completed Sales Orders (Physical Items)
Business Problem:
Merchants need to track only physical items (requiring shipping and fulfillment) for logistics and shipping-cost analysis.
Fields to Retrieve:
ORDER_ID
ORDER_ITEM_SEQ_ID
PRODUCT_ID
PRODUCT_TYPE_ID
SALES_CHANNEL_ENUM_ID
ORDER_DATE
ENTRY_DATE
STATUS_ID
STATUS_DATETIME
ORDER_TYPE_ID
PRODUCT_STORE_ID
select
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

from order_item oi

join product p
on oi.PRODUCT_ID = p.PRODUCT_ID

join order_status os
on oi.order_id = os.order_id

join order_header oh
on oi.order_id = oh.ORDER_ID

join product_type pt
on p.PRODUCT_TYPE_ID = pt.PRODUCT_TYPE_ID

where pt.IS_PHYSICAL= 'Y'
AND oh.status_id='ORDER_COMPLETED'
AND oh.order_type_id='SALES_ORDER';

2 Completed Return Items
Business Problem:
Customer service and finance often need insights into returned items to manage refunds, replacements, and inventory restocking.
Fields to Retrieve:
RETURN_ID
ORDER_ID
PRODUCT_STORE_ID
STATUS_DATETIME
ORDER_NAME
FROM_PARTY_ID
RETURN_DATE
ENTRY_DATE
RETURN_CHANNEL_ENUM_ID
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

3 Single-Return Orders (Last Month)
Business Problem:
The mechandising team needs a list of orders that only have one return.
Fields to Retrieve:
PARTY_ID
FIRST_NAME
SELECT
p.party_id,
p.first_name
FROM person p

JOIN return_header rh
ON p.party_id = rh.from_party_id

GROUP BY p.party_id, p.first_name
HAVING COUNT(DISTINCT rh.return_id) = 1;

4 Returns and Appeasements
Business Problem:
The retailer needs the total amount of items, were returned as well as how many appeasements were issued.
Fields to Retrieve:
TOTAL RETURNS
RETURN $ TOTAL
TOTAL APPEASEMENTS
APPEASEMENTS $ TOTAL
select
sum(ri.RETURN_QUANTITY \* ri.RETURN_PRICE) as 'Total return Amount',
count(DISTINCT ri.RETURN_ID) as 'TOTAL RETURNS',

sum(ra.AMOUNT) as 'Total APPEASEMENTS Amount',
count(DISTINCT ra.RETURN_ADJUSTMENT_ID) as 'TOTAL APPEASEMENTS'

from return_header rh

join return_item ri
on rh.RETURN_ID = ri.RETURN_ID

join return_adjustment ra
on rh.RETURN_ID = ra.RETURN_ID

where RETURN_ADJUSTMENT_TYPE_ID = 'APPEASEMENTS'

5 Detailed Return Information
Business Problem:
Certain teams need granular return data (reason, date, refund amount) for analyzing return rates, identifying recurring issues, or updating policies.
Fields to Retrieve:
RETURN_ID
ENTRY_DATE
RETURN_ADJUSTMENT_TYPE_ID (refund type, store credit, etc.)
AMOUNT
COMMENTS
ORDER_ID
ORDER_DATE
RETURN_DATE
PRODUCT_STORE_ID
select
rh.RETURN_ID,
rh.ENTRY_DATE,
ra.RETURN_ADJUSTMENT_TYPE_ID,
ra.AMOUNT,
ra.COMMENTS,
ri.ORDER_ID,
oh.ORDER_DATE,
rh.RETURN_DATE,
oh.PRODUCT_STORE_ID

from return_header rh

join return_item ri
on rh.RETURN_ID = ri.return_id

join return_adjustment ra
on ri.RETURN_ITEM_SEQ_ID = ra.RETURN_ITEM_SEQ_ID
and ri.return_id = ra.return_id

JOIN order_header oh
on ri.order_id = oh.ORDER_ID

6 Orders with Multiple Returns
Business Problem:
Analyzing orders with multiple returns can identify potential fraud, chronic issues with certain items, or inconsistent shipping processes.
Fields to Retrieve:
ORDER_ID
RETURN_ID
RETURN_DATE
RETURN_REASON
RETURN_QUANTITY
select  
ri.ORDER_ID,
ri.RETURN_ID,
rh.RETURN_DATE,
ri.RETURN_REASON_ID as RETURN_REASON,
ri.RETURN_QUANTITY

from return_header rh

join return_item ri
on rh.return_id = ri.return_id

where ri.ORDER_ID in (SELECT ORDER_ID from return_item group by ORDER_ID having count(ORDER_ID) > 1 );

7 Store with Most One-Day Shipped Orders (Last Month)
Business Problem:
Identify which facility (store) handled the highest volume of “one-day shipping” orders in the previous month, useful for operational benchmarking.
Fields to Retrieve:
FACILITY_ID
FACILITY_NAME
TOTAL_ONE_DAY_SHIP_ORDERS
REPORTING_PERIOD
SELECT
f.facility_id,
f.facility_name,
COUNT(DISTINCT oh.order_id) AS total_one_day_ship_orders,

DATE_FORMAT(
DATE_SUB(CURDATE(), INTERVAL 1 MONTH),'%Y-%m') AS reporting_period

FROM facility f

JOIN shipment s
ON f.facility_id = s.origin_facility_id

JOIN order_header oh
ON s.primary_order_id = oh.order_id

GROUP BY
f.facility_id,
f.facility_name
ORDER BY total_one_day_ship_orders DESC
LIMIT 1;

8 List of Warehouse Pickers
Business Problem:
Warehouse managers need a list of employees responsible for picking and packing orders to manage shifts, productivity, and training needs.
Fields to Retrieve:
PARTY_ID (or Employee ID)
NAME (First/Last)
ROLE_TYPE_ID (e.g., “WAREHOUSE_PICKER”)
FACILITY_ID (assigned warehouse)
STATUS (active or inactive employee)

9 Total Facilities That Sell the Product
Business Problem:
Retailers want to see how many (and which) facilities (stores, warehouses, virtual sites) currently offer a product for sale.
Fields to Retrieve:
PRODUCT_ID
PRODUCT_NAME (or INTERNAL_NAME)
FACILITY_COUNT (number of facilities selling the product)
(Optionally) a list of FACILITY_IDs if more detail is needed

10 Total Items in Various Virtual Facilities
Business Problem:
Retailers need to study the relation of inventory levels of products to the type of facility it's stored at. Retrieve all inventory levels for products at locations and include the facility type Id. Do not retrieve facilities that are of type Virtual.
Fields to Retrieve:
PRODUCT_ID
FACILITY_ID
FACILITY_TYPE_ID
QOH (Quantity on Hand)
ATP (Available to Promise)
select
pf.PRODUCT_ID,
pf.FACILITY_ID,
f.FACILITY_TYPE_ID,
ii.QUANTITY_ON_HAND_TOTAL as QOH ,
ii.AVAILABLE_TO_PROMISE_TOTAL as ATP

from product_facility pf

join FACILITY f
on pf.FACILITY_ID = f.FACILITY_ID

join INVENTORY_item ii
on pf.PRODUCT_ID = ii.PRODUCT_ID
AND pf.facility_id = ii.facility_id;

11 Transfer Orders Without Inventory Reservation
Business Problem:
When transferring stock between facilities, the system should reserve inventory. If it isn’t reserved, the transfer may fail or oversell.
Fields to Retrieve:
TRANSFER_ORDER_ID
FROM_FACILITY_ID
TO_FACILITY_ID
PRODUCT_ID
REQUESTED_QUANTITY
RESERVED_QUANTITY
TRANSFER_DATE
STATUS

12 Orders Without Picklist
Business Problem:
A picklist is necessary for warehouse staff to gather items. Orders missing a picklist might be delayed and need attention.
Fields to Retrieve:
ORDER_ID
ORDER_DATE
ORDER_STATUS
FACILITY_ID
DURATION (How long has the order been assigned at the facility)
