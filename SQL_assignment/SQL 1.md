https://docs.google.com/document/d/1NbIJYdcJmaPYZnR8O8N_JQW9b_7mJpzhlCSIDO5tL90/edit?usp=sharing

1 New Customers Acquired in June 2023
Business Problem:
The marketing team ran a campaign in June 2023 and wants to see how many new customers signed up during that period.
Fields to Retrieve:
PARTY_ID
FIRST_NAME
LAST_NAME
EMAIL
PHONE
ENTRY_DATE
SELECT
p.party_id,
p.first_name,
p.last_name,
email.info_string AS email,
tn.contact_number AS phone,
p.CREATED_STAMP as entry_date
FROM person p

LEFT JOIN party_contact_mech pcm_email
ON p.party_id = pcm_email.party_id

LEFT JOIN contact_mech email
ON pcm_email.contact_mech_id = email.contact_mech_id
AND email.contact_mech_type_id = 'EMAIL_ADDRESS'

LEFT JOIN party_contact_mech pcm_phone
ON p.party_id = pcm_phone.party_id

LEFT JOIN telecom_number tn
ON pcm_phone.contact_mech_id = tn.contact_mech_id

WHERE p.created_stamp >= '2022-06-01' AND p.created_stamp < '2026-07-01';

2 List All Active Physical Products
Business Problem:
Merchandising teams often need a list of all physical products to manage logistics, warehousing, and shipping.
Fields to Retrieve:
PRODUCT_ID
PRODUCT_TYPE_ID
INTERNAL_NAME
SELECT
p.product_id,
p.product_type_id,
p.internal_name
FROM product p
JOIN product_type pt
ON p.product_type_id = pt.product_type_id
WHERE pt.is_physical = 'Y';

3 Products Missing NetSuite ID
Business Problem:
A product cannot sync to NetSuite unless it has a valid NetSuite ID. The OMS needs a list of all products that still need to be created or updated in NetSuite.
Fields to Retrieve:
PRODUCT_ID
INTERNAL_NAME
PRODUCT_TYPE_ID
NETSUITE_ID (or similar field indicating the NetSuite ID; may be NULL or empty if missing)
select p.PRODUCT_ID,p.PRODUCT_TYPE_ID, p.INTERNAL_NAME, GI.iD_VALUE as netsuite_ID from PRODUCT P
LEFT JOIN GOOD_IDENTIFICATION gi
ON p.PRODUCT_ID = gi.PRODUCT_ID
WHERE GOOD_IDENTIFICATION_TYPE_ID = 'ERP_ID'
and gi.ID_VALUE IS NULL;

4 Product IDs Across Systems
Business Problem:
To sync an order or product across multiple systems (e.g., Shopify, HotWax, ERP/NetSuite), the OMS needs to know each system’s unique identifier for that product. This query retrieves the Shopify ID, HotWax ID, and ERP ID (NetSuite ID) for all products.
Fields to Retrieve:
PRODUCT_ID (internal OMS ID)
SHOPIFY_ID
HOTWAX_ID
ERP_ID or NETSUITE_ID (depending on naming)
SELECT
p.product_id,
shopify.id_value as shopify_id,
hotwax.id_value as hotwax_id,
ns.id_value as netsuite_id
FROM product p

LEFT JOIN good_identification shopify
ON p.product_id = shopify.product_id
AND shopify.good_identification_type_id = 'SHOPIFY_PROD_ID'

LEFT JOIN good_identification hotwax
ON p.product_id = hotwax.product_id
AND hotwax.good_identification_type_id = 'HC_code'

LEFT JOIN good_identification ns
ON p.product_id = ns.product_id
AND ns.good_identification_type_id = 'ERP_ID';

5 Completed Orders in August 2023
Business Problem:
After running similar reports for a previous month, you now need all completed orders in August 2023 for analysis.
Fields to Retrieve:
PRODUCT_ID
PRODUCT_TYPE_ID
PRODUCT_STORE_ID
TOTAL_QUANTITY
INTERNAL_NAME
FACILITY_ID
EXTERNAL_ID
FACILITY_TYPE_ID
ORDER_HISTORY_ID
ORDER_ID
ORDER_ITEM_SEQ_ID
SHIP_GROUP_SEQ_ID
SELECT
p.product_id,
p.product_type_id,
oh.product_store_id,
oi.quantity as total_quantity,
p.internal_name,
f.facility_id,
oi.external_id,
f.facility_type_id,
ohis.order_history_id,
oi.order_id,
oi.order_item_seq_id,
oisg.ship_group_seq_id
from product p

JOIN order_item oi
ON p.product_id = oi.product_id

JOIN order_header oh
ON oi.order_id = oh.order_id

LEFT JOIN order_item_ship_group oisg
ON oi.order_id = oisg.order_id
AND oi.ship_group_seq_id = oisg.ship_group_seq_id

LEFT JOIN product_facility pf
ON p.product_id = pf.product_id

LEFT JOIN facility f
ON pf.facility_id = f.facility_id

LEFT JOIN order_history ohis
ON oh.order_id = ohis.order_id

WHERE oh.status_id='ORDER_COMPLETED'

7 Newly Created Sales Orders and Payment Methods
Business Problem:
Finance teams need to see new orders and their payment methods for reconciliation and fraud checks.
Fields to Retrieve:
ORDER_ID
TOTAL_AMOUNT
PAYMENT_METHOD
Shopify Order ID (if applicable)
select oh.ORDER_ID,
oh.GRAND_TOTAL as TOTAL_AMOUNT,
opp.PAYMENT_METHOD_TYPE_ID as 'PAYMENT METHOD ID',
oh.EXTERNAL_ID as 'Shopify Order ID'
from order_header oh
left JOIN order_payment_preference opp
on oh.ORDER_ID = opp.ORDER_ID
where oh.ORDER_TYPE_ID = 'Sales_order'

8 Payment Captured but Not Shipped
Business Problem:
Finance teams want to ensure revenue is recognized properly. If payment is captured but no shipment has occurred, it warrants further review.
Fields to Retrieve:
ORDER_ID
ORDER_STATUS
PAYMENT_STATUS
SHIPMENT_STATUS
select oh.order_id,
oh.STATUS_ID,
opp.STATUS_ID as 'Payment_Status',
s.STATUS_ID as SHIPPING_Status

from order_header oh
left join order_payment_preference opp
on oh.order_id = opp.order_id

left JOIN shipment s
on oh.ORDER_id = s.PRIMARY_ORDER_ID

WHERE
(opp.status_id = 'PAYMENT_SETTLED' or opp.status_id = 'Payment_Received') AND (s.status_id != 'SHIPMENT_SHIPPED' OR s.status_id IS NULL);

9 Orders Completed Hourly
Business Problem:
Operations teams may want to see how orders complete across the day to schedule staffing.
Fields to Retrieve:
TOTAL ORDERS
HOUR

10 BOPIS Orders Revenue (Last Year)
Business Problem:
BOPIS (Buy Online, Pickup In Store) is a key retail strategy. Finance wants to know the revenue from BOPIS orders for the previous year.
Fields to Retrieve:
TOTAL ORDERS
TOTAL REVENUE
SELECT COUNT(DISTINCT oh.ORDER_ID) AS total_orders,

SUM(
CASE
WHEN oisg.shipment_method_type_id = 'STOREPICKUP'
THEN oi.quantity \* oi.unit_price
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

11 Canceled Orders (Last Month)
Business Problem:
The merchandising team needs to know how many orders were canceled in the previous month and their reasons.
Fields to Retrieve:
TOTAL ORDERS
CANCELATION REASON
SELECT
COUNT(DISTINCT oh.order_id) AS total_orders,
os.change_reason AS cancellation_reason
FROM order_header oh
JOIN order_status os
ON oh.order_id = os.order_id
WHERE oh.status_id = 'ORDER_CANCELLED'
GROUP BY os.change_reason;

12 Product Threshold Value
Business Problem The retailer has set a threshild value for products that are sold online, in order to avoid over selling.
Fields to Retrieve:
PRODUCT ID
THRESHOLD

SELECT product_id, minimum_stock as threshold FROM product_facility;
