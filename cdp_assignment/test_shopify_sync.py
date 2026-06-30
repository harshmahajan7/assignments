#!/usr/bin/env python3
import os
import json

SAMPLE_DIR = "/home/harshmahajan/Sandbox/assignments/cdp_assignment/shopify-samples/customers-json"

def transform_shopify_customer(payload, filename):
    customer = payload.get("customer")
    if not customer:
        print(f"[{filename}] Error: No 'customer' object found in payload.")
        return None

    # Basic Info
    shopify_id = str(customer.get("id"))
    first_name = customer.get("first_name") or ""
    last_name = customer.get("last_name") or ""
    email = customer.get("email")
    phone = customer.get("phone")
    verified_email = "Y" if customer.get("verified_email") else "N"
    accepts_marketing = "Y" if customer.get("accepts_marketing") else "N"

    # We mock generating a Party UUID
    party_id = f"P_{shopify_id[:5]}_{first_name[:3].upper()}"

    sql_statements = []
    sql_statements.append(f"-- Processing Shopify Customer ID: {shopify_id} from {filename}")
    
    # 1. Party & Person Insertion
    sql_statements.append(
        f"INSERT INTO Party (party_id, party_type_enum_id) VALUES ('{party_id}', 'PERSON');"
    )
    sql_statements.append(
        f"INSERT INTO Person (party_id, first_name, last_name) VALUES ('{party_id}', '{first_name}', '{last_name}');"
    )
    sql_statements.append(
        f"INSERT INTO PartyRole (party_id, role_type_id) VALUES ('{party_id}', 'Customer');"
    )
    
    # 2. PartyIdentification
    sql_statements.append(
        f"INSERT INTO PartyIdentification (party_id, party_id_type_enum_id, id_value) VALUES ('{party_id}', 'SHOPIFY_CUST_ID', '{shopify_id}');"
    )

    # 3. Email
    if email:
        email_mech_id = f"CM_EM_{shopify_id[:5]}"
        sql_statements.append(
            f"INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) VALUES ('{email_mech_id}', 'EMAIL_ADDRESS', '{email}');"
        )
        sql_statements.append(
            f"INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date, opt_in_ind, verified_ind) VALUES ('{party_id}', '{email_mech_id}', 'PRIMARY_EMAIL', CURRENT_TIMESTAMP, '{accepts_marketing}', '{verified_email}');"
        )

    # 4. Phone
    if phone:
        phone_mech_id = f"CM_PH_{shopify_id[:5]}"
        sql_statements.append(
            f"INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES ('{phone_mech_id}', 'TELECOM_NUMBER');"
        )
        sql_statements.append(
            f"INSERT INTO TelecomNumber (contact_mech_id, contact_number) VALUES ('{phone_mech_id}', '{phone}');"
        )
        sql_statements.append(
            f"INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES ('{party_id}', '{phone_mech_id}', 'PRIMARY_PHONE', CURRENT_TIMESTAMP);"
        )

    # 5. Addresses
    addresses = customer.get("addresses", [])
    addr_count = 0
    for idx, addr in enumerate(addresses):
        address1 = addr.get("address1")
        zip_code = addr.get("zip")
        
        # Skip empty address rows
        if not address1 and not zip_code:
            continue
            
        addr_count += 1
        addr_mech_id = f"CM_AD_{shopify_id[:5]}_{idx}"
        address2 = addr.get("address2") or ""
        city = addr.get("city") or ""
        province = addr.get("province_code") or addr.get("province") or ""
        country = addr.get("country_code") or addr.get("country") or ""
        is_default = addr.get("default", False)
        purpose = "SHIPPING_LOCATION" if is_default else "POSTAL_ADDRESS"

        sql_statements.append(
            f"INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES ('{addr_mech_id}', 'POSTAL_ADDRESS');"
        )
        sql_statements.append(
            f"INSERT INTO PostalAddress (contact_mech_id, address1, address2, city, province_geo_id, postal_code, country_geo_id) VALUES ('{addr_mech_id}', '{address1}', '{address2}', '{city}', '{province}', '{zip_code}', '{country}');"
        )
        sql_statements.append(
            f"INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES ('{party_id}', '{addr_mech_id}', '{purpose}', CURRENT_TIMESTAMP);"
        )

    return {
        "shopify_id": shopify_id,
        "name": f"{first_name} {last_name}".strip(),
        "has_email": email is not None,
        "has_phone": phone is not None,
        "addresses_count": addr_count,
        "sql": sql_statements
    }

def main():
    if not os.path.exists(SAMPLE_DIR):
        print(f"Error: Sample directory not found at {SAMPLE_DIR}")
        return

    print("=" * 80)
    print("CDP Shopify Customer Integration: Sample Payload Verification Test")
    print("=" * 80)

    files = [f for f in os.listdir(SAMPLE_DIR) if f.endswith(".json")]
    files.sort()

    for idx, filename in enumerate(files):
        filepath = os.path.join(SAMPLE_DIR, filename)
        with open(filepath, "r") as f:
            try:
                payload = json.load(f)
                result = transform_shopify_customer(payload, filename)
                if result:
                    print(f"\n[{idx + 1}] File: {filename}")
                    print(f"    Customer Name:    {result['name']}")
                    print(f"    Shopify ID:       {result['shopify_id']}")
                    print(f"    Has Email:        {result['has_email']}")
                    print(f"    Has Phone:        {result['has_phone']}")
                    print(f"    Address Records:  {result['addresses_count']}")
                    print("    Generated SQL DML Trace:")
                    for stmt in result["sql"]:
                        print(f"        {stmt}")
            except Exception as e:
                print(f"Error processing {filename}: {e}")

    print("\n" + "=" * 80)
    print("Test execution finished successfully.")
    print("=" * 80)

if __name__ == "__main__":
    main()
