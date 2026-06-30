# Data Mapping Document: Shopify Customer API to UDM Database

This document details the mapping between the Shopify Customer API and the Universal Data Model (UDM) database schema designed for NotNaked's Customer Data Platform (CDP).

---

## 1. Customer Basic Profile Mapping

| Shopify API Field | UDM Target Table | UDM Target Column | Data Type Mapping & Rules |
| :--- | :--- | :--- | :--- |
| `id` | `PartyIdentification` | `id_value` | **Type Conversion**: Long Integer to `VARCHAR(255)`. Mapped where `party_id_type_enum_id = 'SHOPIFY_CUST_ID'`. |
| `first_name` | `Person` | `first_name` | `VARCHAR(100)`. Mapped directly. |
| `last_name` | `Person` | `last_name` | `VARCHAR(100)`. Mapped directly. |
| `email` | `ContactMech` | `info_string` | `VARCHAR(255)`. Mapped where `contact_mech_type_enum_id = 'EMAIL_ADDRESS'`. |
| `phone` | `TelecomNumber` | `contact_number` | `VARCHAR(40)`. Mapped where `ContactMech.contact_mech_type_enum_id = 'TELECOM_NUMBER'`. |
| `verified_email` | `PartyContactMech` | `verified_ind` | **Type Conversion**: Boolean to `CHAR(1)` (`Y` for `true`, `N` for `false`). |
| `accepts_marketing` | `PartyContactMech` | `opt_in_ind` | **Type Conversion**: Boolean to `CHAR(1)` (`Y` for `true`, `N` for `false`). |

---

## 2. Address Array Mapping (`addresses`)

Shopify provides customer addresses as an array of objects under the `addresses` key. In our UDM-based MySQL schema, multiple addresses are stored as separate rows in `ContactMech` and `PostalAddress` tables, linked to the customer via `PartyContactMech` with distinct purposes (e.g., shipping, billing).

| Shopify Address Field | UDM Target Table | UDM Target Column | Data Type Mapping & Rules |
| :--- | :--- | :--- | :--- |
| `address1` | `PostalAddress` | `address1` | `VARCHAR(255)`. Mapped directly. |
| `address2` | `PostalAddress` | `address2` | `VARCHAR(255)`. Mapped directly (nullable). |
| `city` | `PostalAddress` | `city` | `VARCHAR(100)`. Mapped directly. |
| `province` / `province_code`| `PostalAddress` | `province_geo_id` | `VARCHAR(40)`. Code (e.g., `NY`, `CA`) is preferred for standardization. |
| `zip` | `PostalAddress` | `postal_code` | `VARCHAR(40)`. Mapped directly. |
| `country` / `country_code`| `PostalAddress` | `country_geo_id` | `VARCHAR(40)`. 2-character ISO country code (e.g., `US`, `IN`) is stored. |
| `phone` | `TelecomNumber` | `contact_number` | If an address contains a phone number, it is stored as a separate `TelecomNumber` contact mechanism. It is associated with the party and linked to this address's contact mechanism using a purpose prefix/link or stored under a purpose like `SHIPPING_PHONE`. |
| `default` | `PartyContactMech` | `contact_mech_purpose_enum_id`| **Conditional Mapping**: If `default` is `true`, maps to purpose `SHIPPING_LOCATION` or `POSTAL_SHIPPING_DEST`. Otherwise, maps to `POSTAL_ADDRESS` or `POSTAL_GENERAL`. |

---

## 3. Data Transformations & Edge Case Handling

### 3.1. Primary Key Generation (`party_id` and `contact_mech_id`)
* **Shopify Customer ID to Party UUID**: Shopify customer IDs (e.g., `7194240516349`) are unique. However, the UDM schema uses UUID-style strings (`VARCHAR(40)`) to remain system-agnostic (supporting future integrations like Salesforce or NetSuite).
* **Generation Strategy**: When syncing a customer for the first time:
  1. We search the `PartyIdentification` table for an existing row where `party_id_type_enum_id = 'SHOPIFY_CUST_ID'` and `id_value = shopify_customer_id`.
  2. If found, we reuse that `party_id` (this is the key to preventing duplicate customer records).
  3. If not found, we check if another customer exists with the same primary `email` (using `ContactMech` and `PartyContactMech` records). If found, we link the Shopify ID to that `party_id`.
  4. If no match is found by ID or Email, we generate a new UUID for `party_id`.
* **Contact Mechanism IDs**: Generated sequentially or using UUIDs during import.

### 3.2. Data Type Differences
* **Booleans to Character Indicators**: Boolean values in the Shopify JSON (`true`/`false`) must be converted to `CHAR(1)` values `Y` or `N` to match the MySQL DDL.
* **Phone Numbers**: Shopify phone numbers are single strings (e.g., `"+12127654321"`). We store them in the `contact_number` column. If country code or area code can be parsed, they are populated in `country_code` and `area_code` respectively, though `contact_number` holds the full string as the fallback.

### 3.3. Multi-Valued Fields (`addresses`)
Since `addresses` is a list, we:
1. Iterate over each address in the list.
2. Deduplicate addresses by checking if the customer already has an active `PostalAddress` with the same `address1` and `postal_code`.
3. Map the Shopify address attributes to a new `PostalAddress` record.
4. Set the `PartyContactMech` purpose:
   * If `default = true` in the Shopify JSON, set purpose as `SHIPPING_LOCATION`.
   * If `default = false`, set purpose as `POSTAL_ADDRESS`.

---

## 4. Transformation Example

### 4.1. Input Shopify JSON (Subset)
```json
{
  "customer": {
    "id": 7194240516349,
    "email": "adam.smith@example.com",
    "first_name": "Adam",
    "last_name": "Smith",
    "phone": "+12127654321",
    "verified_email": true,
    "accepts_marketing": true,
    "addresses": [
      {
        "address1": "456 Park Avenue",
        "address2": "Central Suite",
        "city": "New York",
        "province_code": "NY",
        "country_code": "US",
        "zip": "10022",
        "phone": "+12121234567",
        "default": true
      }
    ]
  }
}
```

### 4.2. Target Database Insert Trace (Conceptual)

Assuming `party_id = 'P-10001'` is generated/resolved, and new contact mechanism IDs are generated.

#### 1. Party & Person Insertion
```sql
INSERT INTO Party (party_id, party_type_enum_id) 
VALUES ('P-10001', 'PERSON');

INSERT INTO Person (party_id, first_name, last_name) 
VALUES ('P-10001', 'Adam', 'Smith');
```

#### 2. Shopify ID Registration
```sql
INSERT INTO PartyIdentification (party_id, party_id_type_enum_id, id_value) 
VALUES ('P-10001', 'SHOPIFY_CUST_ID', '7194240516349');
```

#### 3. Primary Email Registration
```sql
-- Create Contact Mechanism for Email
INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) 
VALUES ('CM-EMAIL-01', 'EMAIL_ADDRESS', 'adam.smith@example.com');

-- Associate Email with Party (including opt-in and verification)
INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date, opt_in_ind, verified_ind) 
VALUES ('P-10001', 'CM-EMAIL-01', 'PRIMARY_EMAIL', CURRENT_TIMESTAMP, 'Y', 'Y');
```

#### 4. Primary Phone Registration
```sql
-- Create Contact Mechanism for Phone
INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) 
VALUES ('CM-PHONE-01', 'TELECOM_NUMBER');

-- Insert Phone Details
INSERT INTO TelecomNumber (contact_mech_id, contact_number) 
VALUES ('CM-PHONE-01', '+12127654321');

-- Associate Phone with Party
INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) 
VALUES ('P-10001', 'CM-PHONE-01', 'PRIMARY_PHONE', CURRENT_TIMESTAMP);
```

#### 5. Address Registration
```sql
-- Create Contact Mechanism for Postal Address
INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) 
VALUES ('CM-ADDR-01', 'POSTAL_ADDRESS');

-- Insert Postal Address Details
INSERT INTO PostalAddress (contact_mech_id, address1, address2, city, province_geo_id, postal_code, country_geo_id) 
VALUES ('CM-ADDR-01', '456 Park Avenue', 'Central Suite', 'New York', 'NY', '10022', 'US');

-- Associate Address with Party (Since default is true, purpose is SHIPPING_LOCATION)
INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) 
VALUES ('P-10001', 'CM-ADDR-01', 'SHIPPING_LOCATION', CURRENT_TIMESTAMP);
```
