https://docs.google.com/document/d/1NbIJYdcJmaPYZnR8O8N_JQW9b_7mJpzhlCSIDO5tL90/edit?usp=sharing

5. Mixed Party + Order Queries
   5.1 Shipping Addresses for October 2023 Orders
   Business Problem:
   Customer Service might need to verify addresses for orders placed or completed in October 2023. This helps ensure shipments are delivered correctly and prevents address-related issues.
   Fields to Retrieve:
   ORDER_ID
   PARTY_ID (Customer ID)
   CUSTOMER_NAME (or FIRST_NAME / LAST_NAME)
   STREET_ADDRESS
   CITY
   STATE_PROVINCE
   POSTAL_CODE
   COUNTRY_CODE
   ORDER_STATUS
   ORDER_DATE
   select
   oh.ORDER_ID,
   p.PARTY_ID,
   p.first_name as CUSTOMER_NAME,
   pa.ADDRESS1 as STREET_ADDRESS,
   pa.CITY,
   pa.STATE_PROVINCE_GEO_ID as STATE_PROVINCE,
   pa.POSTAL_CODE,
   pa.COUNTRY_GEO_ID as COUNTRY_CODE,
   oh.STATUS_ID as ORDER_STATUS,
   oh.ORDER_DATE
   from person p

join order_role orr
on p.party_id = orr.PARTY_ID

join order_header oh
on orr.ORDER_ID = oh.ORDER_ID

join party_contact_mech pcm
on p.PARTY_ID = pcm.PARTY_ID

join postal_address pa
on pcm.CONTACT_MECH_ID = pa.CONTACT_MECH_ID

WHERE orr.role_type_id='PLACING_CUSTOMER';
(there are many people or organization are invovled in this order fulfillment process. We want only the details of customer)

5.2 Orders from New York
Business Problem:
Companies often want region-specific analysis to plan local marketing, staffing, or promotions in certain areas—here, specifically, New York.
Fields to Retrieve:
ORDER_ID
CUSTOMER_NAME
STREET_ADDRESS (or shipping address detail)
CITY
STATE_PROVINCE
POSTAL_CODE
TOTAL_AMOUNT
ORDER_DATE
ORDER_STATUS
SELECT
oh.order_id,
pa.to_name AS customer_name,
pa.address1 AS street_address,
pa.city,
pa.state_province_geo_id AS state_province,
pa.postal_code,
oh.grand_total AS total_amount,
oh.order_date,
oh.status_id AS order_status

FROM order_header oh

JOIN order_role orr
ON oh.order_id = orr.order_id

JOIN party_contact_mech pcm
ON orr.party_id = pcm.party_id

LEFT JOIN postal_address pa
ON pcm.contact_mech_id = pa.contact_mech_id

WHERE orr.role_type_id='PLACING_CUSTOMER'
AND pa.city='New York';

5.3 Top-Selling Product in New York
Business Problem:
Merchandising teams need to identify the best-selling product(s) in a specific region (New York) for targeted restocking or promotions.
Fields to Retrieve:
PRODUCT_ID
INTERNAL_NAME
TOTAL_QUANTITY_SOLD
CITY / STATE (within New York region)
REVENUE (optionally, total sales amount)
SELECT
p.product_id,
p.internal_name,
SUM(oi.quantity) AS total_quantity_sold,
pa.city,
pa.state_province_geo_id AS state

FROM product p

JOIN order_item oi
ON p.product_id = oi.product_id

JOIN order_role orr
ON oi.order_id = orr.order_id

JOIN party_contact_mech pcm
ON orr.party_id = pcm.party_id

JOIN postal_address pa
ON pcm.contact_mech_id = pa.contact_mech_id

WHERE orr.role_type_id='PLACING_CUSTOMER'
AND pa.city='New York'

GROUP BY p.product_id;

7.3 Store-Specific (Facility-Wise) Revenue
Business Problem:
Different physical or online stores (facilities) may have varying levels of performance. The business wants to compare revenue across facilities for sales planning and budgeting.
Fields to Retrieve:
FACILITY_ID
FACILITY_NAME
TOTAL_ORDERS
TOTAL_REVENUE
DATE_RANGE
SELECT
f.facility_id,
f.facility_name,

    COUNT(DISTINCT oi.order_id) AS total_orders,

    SUM(oi.quantity * oi.unit_price) AS total_revenue

FROM order_item oi

JOIN order_item_ship_group oisg
ON oi.order_id = oisg.order_id
AND oi.ship_group_seq_id = oisg.ship_group_seq_id

JOIN facility f
ON oisg.facility_id = f.facility_id

JOIN order_header oh
ON oi.order_id = oh.order_id

WHERE oh.order_type_id='SALES_ORDER'

GROUP BY
f.facility_id,
f.facility_name;

8. Inventory Management & Transfers
   8.1 Lost and Damaged Inventory
   Business Problem:
   Warehouse managers need to track “shrinkage” such as lost or damaged inventory to reconcile physical vs. system counts.
   Fields to Retrieve:
   INVENTORY_ITEM_ID
   PRODUCT_ID
   FACILITY_ID
   QUANTITY_LOST_OR_DAMAGED
   REASON_CODE (Lost, Damaged, Expired, etc.)
   TRANSACTION_DATE
   SELECT
   ii.inventory_item_id,
   ii.product_id,
   ii.facility_id,
   iid.quantity_on_hand_diff AS quantity_lost_or_damaged,
   iid.reason_enum_id AS reason_code,
   iid.effective_date AS transaction_date

FROM inventory_item ii

JOIN inventory_item_detail iid
ON ii.inventory_item_id = iid.inventory_item_id

WHERE iid.reason_enum_id IN ('VAR_LOST','VAR_DAMAGED','EXPIRED');

8.2 Low Stock or Out of Stock Items Report
Business Problem:
Avoiding out-of-stock situations is critical. This report flags items that have fallen below a certain reorder threshold or have zero available stock.
Fields to Retrieve:
PRODUCT_ID
PRODUCT_NAME
FACILITY_ID
QOH (Quantity on Hand)
ATP (Available to Promise)
REORDER_THRESHOLD
DATE_CHECKED
SELECT
p.PRODUCT_ID,
p.PRODUCT_NAME,
pf.FACILITY_ID,

ii.QUANTITY_ON_HAND_TOTAL as QOH,
ii.AVAILABLE_TO_PROMISE_TOTAL as ATP ,

pf.MINIMUM_STOCK as REORDER_THRESHOLD

from product p

join product_facility pf
on p.PRODUCT_ID = pf.PRODUCT_ID

join inventory_item ii
on p.PRODUCT_ID = ii.PRODUCT_ID
AND pf.facility_id = ii.facility_id

8.3 Retrieve the Current Facility (Physical or Virtual) of Open Orders
Business Problem:
The business wants to know where open orders are currently assigned, whether in a physical store or a virtual facility (e.g., a distribution center or online fulfillment location).
Fields to Retrieve:
ORDER_ID
ORDER_STATUS
FACILITY_ID
FACILITY_NAME
FACILITY_TYPE_ID
SELECT
oh.order_id,
oh.status_id AS order_status,
f.facility_id,
f.facility_name,
f.facility_type_id

FROM order_header oh

JOIN order_item oi
ON oh.order_id = oi.order_id

JOIN order_item_ship_group oisg
ON oi.order_id = oisg.order_id
AND oi.ship_group_seq_id = oisg.ship_group_seq_id

JOIN facility f
ON oisg.facility_id = f.facility_id

WHERE oh.status_id NOT IN ('ORDER_COMPLETED','ORDER_CANCELLED')
GROUP BY oh.order_id;

8.4 Items Where QOH and ATP Differ
Business Problem:
Sometimes the Quantity on Hand (QOH) doesn’t match the Available to Promise (ATP) due to pending orders, reservations, or data discrepancies. This needs review for accurate fulfillment planning.
Fields to Retrieve:
PRODUCT_ID
FACILITY_ID
QOH (Quantity on Hand)
ATP (Available to Promise)
DIFFERENCE (QOH - ATP)
SELECT
product_id,
facility_id,
quantity_on_hand_total AS QOH,
available_to_promise_total AS ATP,
(quantity_on_hand_total - available_to_promise_total) AS DIFFERENCE

FROM inventory_item

WHERE quantity_on_hand_total != available_to_promise_total;

8.5 Order Item Current Status Changed Date-Time
Business Problem:
Operations teams need to audit when an order item’s status (e.g., from “Pending” to “Shipped”) was last changed, for shipment tracking or dispute resolution.
Fields to Retrieve:
ORDER_ID
ORDER_ITEM_SEQ_ID
CURRENT_STATUS_ID
STATUS_CHANGE_DATETIME
CHANGED_BY
SELECT
oh.order_id,
oi.order_item_seq_id,
os.status_id AS current_status_id,
os.status_datetime AS status_change_datetime,
os.status_user_login AS changed_by

FROM order_header oh

JOIN order_item oi
ON oh.order_id = oi.order_id

JOIN order_status os
ON oh.order_id = os.order_id
AND oi.order_item_seq_id = os.order_item_seq_id;

8.6 Total Orders by Sales Channel
Business Problem:
Marketing and sales teams want to see how many orders come from each channel (e.g., web, mobile app, in-store POS, marketplace) to allocate resources effectively.
Fields to Retrieve:
SALES_CHANNEL
TOTAL_ORDERS
TOTAL_REVENUE
REPORTING_PERIOD
select
oh.SALES_CHANNEL_ENUM_ID as SALES_CHANNEL,
count(DISTINCT oh.ORDER_ID) as TOTAL_ORDERS,
sum(oi.QUANTITY \* oi.UNIT_PRICE) as TOTAL_REVENUE

from order_header oh

join order_item oi
on oh.ORDER_ID = oi.ORDER_ID

where ORDER_TYPE_ID = 'SALES_ORDER'
GROUP by oh.sales_channel_enum_id;
