# Data Access Logic & Shopify Integration Pseudo-code

This document describes the logic for accessing, manipulating, and integrating customer data within the Customer Data Platform (CDP) for NotNaked. It provides both structural pseudo-code and concrete Moqui Framework XML service patterns.

---

## 1. CDP Customer CRUD Operations

### 1.1. Create Customer Profile
This operation creates a new customer, registers their basic details, and initializes their primary contact mechanisms.

#### Pseudo-code:
```python
def createCustomerProfile(firstName, lastName, emailAddress, contactNumber, acceptsMarketing, externalId):
    # 1. Validation
    if isEmpty(firstName) or isEmpty(lastName):
        raise ValidationError("First name and last name are required.")
    
    if emailAddress and not isValidEmail(emailAddress):
        raise ValidationError("Invalid email address format.")

    # Start Transaction
    beginTransaction()
    try:
        # 2. Create base Party
        partyId = generateUUID()
        execute_sql(
            "INSERT INTO Party (party_id, party_type_enum_id) VALUES (?, 'PERSON')", 
            [partyId]
        )
        
        # 3. Create Person subtype
        execute_sql(
            "INSERT INTO Person (party_id, first_name, last_name) VALUES (?, ?, ?)", 
            [partyId, firstName, lastName]
        )

        # 4. Associate External ID (e.g. Shopify ID) if provided
        if externalId:
            execute_sql(
                "INSERT INTO PartyIdentification (party_id, party_id_type_enum_id, id_value) VALUES (?, 'SHOPIFY_CUST_ID', ?)", 
                [partyId, externalId]
            )

        # 5. Create primary Email ContactMech
        if emailAddress:
            emailMechId = generateUUID()
            execute_sql(
                "INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) VALUES (?, 'EMAIL_ADDRESS', ?)", 
                [emailMechId, emailAddress]
            )
            optInVal = 'Y' if acceptsMarketing else 'N'
            execute_sql(
                "INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date, opt_in_ind) VALUES (?, ?, 'PRIMARY_EMAIL', CURRENT_TIMESTAMP, ?)", 
                [partyId, emailMechId, optInVal]
            )

        # 6. Create primary Phone ContactMech
        if contactNumber:
            phoneMechId = generateUUID()
            execute_sql(
                "INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'TELECOM_NUMBER')", 
                [phoneMechId]
            )
            execute_sql(
                "INSERT INTO TelecomNumber (contact_mech_id, contact_number) VALUES (?, ?)", 
                [phoneMechId, contactNumber]
            )
            execute_sql(
                "INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES (?, ?, 'PRIMARY_PHONE', CURRENT_TIMESTAMP)", 
                [partyId, phoneMechId]
            )

        commitTransaction()
        return partyId

    except DatabaseException as e:
        rollbackTransaction()
        raise SystemError(f"Failed to create customer: {e}")
```

---

### 1.2. Retrieve Customer Profile
Retrieves a customer's basic details, external identities, active contact methods (emails, phones, postal addresses), and preferences.

#### Pseudo-code:
```python
def retrieveCustomerProfile(partyId):
    # 1. Retrieve Person Details
    person = execute_sql("SELECT first_name, last_name, date_of_birth FROM Person WHERE party_id = ?", [partyId])
    if not person:
        raise NotFoundError(f"No customer found for ID: {partyId}")
        
    profile = {
        "partyId": partyId,
        "firstName": person.first_name,
        "lastName": person.last_name,
        "dateOfBirth": person.date_of_birth,
        "identities": [],
        "emails": [],
        "phones": [],
        "addresses": [],
        "preferences": {}
    }

    # 2. Retrieve External Identities
    identities = execute_sql("SELECT party_id_type_enum_id, id_value FROM PartyIdentification WHERE party_id = ?", [partyId])
    for ident in identities:
        profile["identities"].append({
            "type": ident.party_id_type_enum_id,
            "value": ident.id_value
        })

    # 3. Retrieve Active Contact Mechanisms
    contactMechs = execute_sql("""
        SELECT cm.contact_mech_id, cm.contact_mech_type_enum_id, cm.info_string, pcm.contact_mech_purpose_enum_id, pcm.opt_in_ind, pcm.verified_ind
        FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        WHERE pcm.party_id = ? AND (pcm.thru_date IS NULL OR pcm.thru_date > CURRENT_TIMESTAMP)
    """, [partyId])

    for cm in contactMechs:
        if cm.contact_mech_type_enum_id == 'EMAIL_ADDRESS':
            profile["emails"].append({
                "contactMechId": cm.contact_mech_id,
                "email": cm.info_string,
                "purpose": cm.contact_mech_purpose_enum_id,
                "acceptsMarketing": cm.opt_in_ind == 'Y',
                "verified": cm.verified_ind == 'Y'
            })
            
        elif cm.contact_mech_type_enum_id == 'TELECOM_NUMBER':
            phone = execute_sql("SELECT country_code, area_code, contact_number FROM TelecomNumber WHERE contact_mech_id = ?", [cm.contact_mech_id])
            profile["phones"].append({
                "contactMechId": cm.contact_mech_id,
                "phoneNumber": phone.contact_number,
                "purpose": cm.contact_mech_purpose_enum_id
            })

        elif cm.contact_mech_type_enum_id == 'POSTAL_ADDRESS':
            addr = execute_sql("SELECT address1, address2, city, province_geo_id, postal_code, country_geo_id FROM PostalAddress WHERE contact_mech_id = ?", [cm.contact_mech_id])
            profile["addresses"].append({
                "contactMechId": cm.contact_mech_id,
                "address1": addr.address1,
                "address2": addr.address2,
                "city": addr.city,
                "province": addr.province_geo_id,
                "zip": addr.postal_code,
                "country": addr.country_geo_id,
                "purpose": cm.contact_mech_purpose_enum_id
            })

    # 4. Retrieve Customer Preferences
    preferences = execute_sql("SELECT preference_key, preference_value FROM CustomerPreference WHERE party_id = ?", [partyId])
    for pref in preferences:
        profile["preferences"][pref.preference_key] = pref.preference_value

    return profile
```

---

### 1.3. Update Customer Profile
Updates a customer's basic details and handles contact method changes. To preserve audit history, existing contact mechanisms are expired (soft-modified), and new ones are inserted.

#### Pseudo-code:
```python
def updateCustomerProfile(partyId, firstName=None, lastName=None, emailAddress=None, addressUpdate=None):
    beginTransaction()
    try:
        # 1. Update basic Person info
        if firstName or lastName:
            update_fields = {}
            if firstName: update_fields["first_name"] = firstName
            if lastName: update_fields["last_name"] = lastName
            
            set_clause = ", ".join([f"{k} = ?" for k in update_fields.keys()])
            execute_sql(f"UPDATE Person SET {set_clause} WHERE party_id = ?", list(update_fields.values()) + [partyId])

        # 2. Update Primary Email (expire old, insert new if changed)
        if emailAddress:
            currentEmail = execute_sql("""
                SELECT cm.contact_mech_id, cm.info_string, pcm.from_date
                FROM PartyContactMech pcm
                JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
                WHERE pcm.party_id = ? AND pcm.contact_mech_purpose_enum_id = 'PRIMARY_EMAIL' AND pcm.thru_date IS NULL
            """, [partyId])

            if not currentEmail or currentEmail.info_string != emailAddress:
                if currentEmail:
                    # Expire old email relationship
                    execute_sql(
                        "UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP WHERE party_id = ? AND contact_mech_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_EMAIL' AND from_date = ?", 
                        [partyId, currentEmail.contact_mech_id, currentEmail.from_date]
                    )
                
                # Insert new email contact mech
                newEmailMechId = generateUUID()
                execute_sql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) VALUES (?, 'EMAIL_ADDRESS', ?)", [newEmailMechId, emailAddress])
                execute_sql("INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES (?, ?, 'PRIMARY_EMAIL', CURRENT_TIMESTAMP)", [partyId, newEmailMechId])

        # 3. Update Addresses (e.g., Shipping Address)
        if addressUpdate:
            # Expire active Shipping address
            currentAddr = execute_sql("""
                SELECT contact_mech_id, from_date FROM PartyContactMech 
                WHERE party_id = ? AND contact_mech_purpose_enum_id = 'SHIPPING_LOCATION' AND thru_date IS NULL
            """, [partyId])
            
            if currentAddr:
                execute_sql(
                    "UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP WHERE party_id = ? AND contact_mech_id = ? AND contact_mech_purpose_enum_id = 'SHIPPING_LOCATION' AND from_date = ?", 
                    [partyId, currentAddr.contact_mech_id, currentAddr.from_date]
                )

            # Insert new Postal Address
            newAddrMechId = generateUUID()
            execute_sql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'POSTAL_ADDRESS')", [newAddrMechId])
            execute_sql("""
                INSERT INTO PostalAddress (contact_mech_id, address1, address2, city, province_geo_id, postal_code, country_geo_id) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [newAddrMechId, addressUpdate['address1'], addressUpdate.get('address2'), addressUpdate['city'], addressUpdate['province'], addressUpdate['zip'], addressUpdate['country']])
            
            execute_sql("INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES (?, ?, 'SHIPPING_LOCATION', CURRENT_TIMESTAMP)", [partyId, newAddrMechId])

        commitTransaction()
    except Exception as e:
        rollbackTransaction()
        raise SystemError(f"Profile update failed: {e}")
```

---

### 1.4. Soft Delete Customer Profile
**Implications of Hard Deletes**: A hard delete (`DELETE FROM Party WHERE party_id = ...`) is highly discouraged in a CDP. It violates database referential integrity by breaking foreign keys associated with historical tables (e.g., Order headers, payments, customer service tickets) or forces cascading deletions that erase valuable business records.
**Soft Delete Strategy**:
1. Expire all contact mechanisms by setting their `thru_date` to `CURRENT_TIMESTAMP`. This immediately removes them from active lists.
2. Disable the customer record in the `Party` table (using a status field like `party_type_enum_id` or a status code) to prevent future transactions while preserving the ID and details for analytics/reporting.

#### Pseudo-code:
```python
def softDeleteCustomerProfile(partyId):
    beginTransaction()
    try:
        # 1. Expire all active contact mechanisms
        execute_sql(
            "UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP WHERE party_id = ? AND (thru_date IS NULL OR thru_date > CURRENT_TIMESTAMP)", 
            [partyId]
        )

        # 2. Mark the Party as disabled / inactive
        # In Moqui, this is typically done by setting statusId = 'PartyDisabled'
        execute_sql(
            "UPDATE Party SET party_type_enum_id = 'DISABLED_PERSON' WHERE party_id = ?", 
            [partyId]
        )

        commitTransaction()
        return True
    except Exception as e:
        rollbackTransaction()
        raise SystemError(f"Soft delete failed: {e}")
```

---

## 2. Shopify Customer Integration Logic

This section outlines the process of retrieving data from Shopify, transforming it, and storing/upserting it into the UDM.

### 2.1. Retrieve Customer Data from Shopify Customer API
Handles API requests, rate limiting (HTTP 429), and pagination using the standard HTTP `Link` header.

#### Pseudo-code:
```python
import time
import requests

def fetchShopifyCustomers(shopUrl, apiToken, limit=50):
    url = f"https://{shopUrl}/admin/api/2024-01/customers.json?limit={limit}"
    headers = {
        "X-Shopify-Access-Token": apiToken,
        "Content-Type": "application/json"
    }

    all_customers = []

    while url:
        response = requests.get(url, headers=headers)
        
        # Handle Rate Limiting (429 Too Many Requests)
        if response.status_code == 429:
            retry_after = int(response.headers.get("Retry-After", 2))
            time.sleep(retry_after)
            continue
            
        if response.status_code != 200:
            raise ApiException(f"Shopify API Error: {response.status_code} - {response.text}")
            
        data = response.json()
        all_customers.extend(data.get("customers", []))

        # Handle Pagination via Link Header
        # Header format: <https://shop.myshopify.com/admin/api/.../customers.json?page_info=xxx>; rel="next"
        link_header = response.headers.get("Link")
        url = None
        if link_header:
            links = link_header.split(",")
            for link in links:
                if 'rel="next"' in link:
                    url = link.split(";")[0].strip("< >")
                    
    return all_customers
```

---

### 2.2. Transformed Store / Upsert Customer (Shopify Sync)
Implements robust conflict and duplicate resolution during data sync.

#### Duplicate / Conflict Resolution Rules:
1. **Search by external ID**: Check if a record exists in `PartyIdentification` where `party_id_type_enum_id = 'SHOPIFY_CUST_ID'` and `id_value = shopify_customer_id`. If found, we update that Party.
2. **Search by Email**: If no Shopify ID match is found, check if a party already exists in the system with the exact primary email address. If found, we "link" the Shopify customer to this existing Party ID by inserting a new `PartyIdentification` record. This merges the profiles and prevents duplicate entries for the same person.
3. **Insert New**: If neither matches, create a brand-new Party and Person.

#### Pseudo-code:
```python
def syncShopifyCustomer(shopifyCustomerPayload):
    shopifyCust = shopifyCustomerPayload.get("customer")
    if not shopifyCust or not shopifyCust.get("id"):
        raise ValueError("Payload missing required customer ID")

    shopifyId = str(shopifyCust["id"])
    email = shopifyCust.get("email")
    phone = shopifyCust.get("phone")

    beginTransaction()
    try:
        partyId = None

        # Rule 1: Find by Shopify ID
        existingIdent = execute_sql("""
            SELECT party_id FROM PartyIdentification 
            WHERE party_id_type_enum_id = 'SHOPIFY_CUST_ID' AND id_value = ?
        """, [shopifyId])

        if existingIdent:
            partyId = existingIdent.party_id
            # Update Person basic info
            execute_sql("""
                UPDATE Person SET first_name = ?, last_name = ? 
                WHERE party_id = ?
            """, [shopifyCust.get("first_name"), shopifyCust.get("last_name"), partyId])
        else:
            # Rule 2: Find by Email
            if email:
                existingEmail = execute_sql("""
                    SELECT pcm.party_id 
                    FROM PartyContactMech pcm
                    JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
                    WHERE cm.contact_mech_type_enum_id = 'EMAIL_ADDRESS' AND cm.info_string = ? AND pcm.thru_date IS NULL
                """, [email])
                if existingEmail:
                    partyId = existingEmail.party_id
            
            # Rule 3: Insert new Party if not found
            if not partyId:
                partyId = generateUUID()
                execute_sql("INSERT INTO Party (party_id, party_type_enum_id) VALUES (?, 'PERSON')", [partyId])
                execute_sql("INSERT INTO Person (party_id, first_name, last_name) VALUES (?, ?, ?)", [partyId, shopifyCust.get("first_name"), shopifyCust.get("last_name")])
                execute_sql("INSERT INTO PartyRole (party_id, role_type_id) VALUES (?, 'Customer')", [partyId])
            
            # Create/link Shopify ID identity
            execute_sql("""
                INSERT INTO PartyIdentification (party_id, party_id_type_enum_id, id_value) 
                VALUES (?, 'SHOPIFY_CUST_ID', ?)
            """, [partyId, shopifyId])

        # Sync Email Address
        if email:
            syncEmailContactMech(partyId, email, shopifyCust.get("verified_email"), shopifyCust.get("accepts_marketing"))

        # Sync Phone Number
        if phone:
            syncPhoneContactMech(partyId, phone)

        # Sync Addresses list
        addresses = shopifyCust.get("addresses", [])
        for addr in addresses:
            # Skip addresses with empty structural data
            if not addr.get("address1") and not addr.get("zip"):
                continue
            syncAddressContactMech(partyId, addr)

        commitTransaction()
        return partyId
    except Exception as e:
        rollbackTransaction()
        raise SystemError(f"Shopify customer sync failed: {e}")


def syncEmailContactMech(partyId, email, verified, acceptsMarketing):
    # Check if this email is already active for this customer
    existing = execute_sql("""
        SELECT cm.contact_mech_id FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        WHERE pcm.party_id = ? AND cm.contact_mech_type_enum_id = 'EMAIL_ADDRESS' AND cm.info_string = ? AND pcm.thru_date IS NULL
    """, [partyId, email])

    optInInd = 'Y' if acceptsMarketing else 'N'
    verifiedInd = 'Y' if verified else 'N'

    if not existing:
        # Expire older primary emails if they exist
        execute_sql("""
            UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP 
            WHERE party_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_EMAIL' AND thru_date IS NULL
        """, [partyId])

        emailMechId = generateUUID()
        execute_sql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) VALUES (?, 'EMAIL_ADDRESS', ?)", [emailMechId, email])
        execute_sql("""
            INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date, opt_in_ind, verified_ind) 
            VALUES (?, ?, 'PRIMARY_EMAIL', CURRENT_TIMESTAMP, ?, ?)
        """, [partyId, emailMechId, optInInd, verifiedInd])
    else:
        # Update marketing preference and verification status on current email
        execute_sql("""
            UPDATE PartyContactMech SET opt_in_ind = ?, verified_ind = ? 
            WHERE party_id = ? AND contact_mech_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_EMAIL'
        """, [optInInd, verifiedInd, partyId, existing.contact_mech_id])


def syncPhoneContactMech(partyId, phone):
    existing = execute_sql("""
        SELECT cm.contact_mech_id FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        JOIN TelecomNumber tn ON cm.contact_mech_id = tn.contact_mech_id
        WHERE pcm.party_id = ? AND cm.contact_mech_type_enum_id = 'TELECOM_NUMBER' AND tn.contact_number = ? AND pcm.thru_date IS NULL
    """, [partyId, phone])

    if not existing:
        # Expire older primary phones
        execute_sql("""
            UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP 
            WHERE party_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_PHONE' AND thru_date IS NULL
        """, [partyId])

        phoneMechId = generateUUID()
        execute_sql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'TELECOM_NUMBER')", [phoneMechId])
        execute_sql("INSERT INTO TelecomNumber (contact_mech_id, contact_number) VALUES (?, ?)", [phoneMechId, phone])
        execute_sql("""
            INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) 
            VALUES (?, ?, 'PRIMARY_PHONE', CURRENT_TIMESTAMP)
        """, [partyId, phoneMechId])


def syncAddressContactMech(partyId, addr):
    # Check if address already registered and active
    existing = execute_sql("""
        SELECT cm.contact_mech_id FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        JOIN PostalAddress pa ON cm.contact_mech_id = pa.contact_mech_id
        WHERE pcm.party_id = ? AND cm.contact_mech_type_enum_id = 'POSTAL_ADDRESS' 
          AND pa.address1 = ? AND pa.postal_code = ? AND pcm.thru_date IS NULL
    """, [partyId, addr.get("address1"), addr.get("zip")])

    purpose = 'SHIPPING_LOCATION' if addr.get("default") else 'POSTAL_ADDRESS'

    if not existing:
        # If it's a new default address, expire old SHIPPING_LOCATION address
        if addr.get("default"):
            execute_sql("""
                UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP 
                WHERE party_id = ? AND contact_mech_purpose_enum_id = 'SHIPPING_LOCATION' AND thru_date IS NULL
            """, [partyId])

        addrMechId = generateUUID()
        execute_sql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'POSTAL_ADDRESS')", [addrMechId])
        execute_sql("""
            INSERT INTO PostalAddress (contact_mech_id, address1, address2, city, province_geo_id, postal_code, country_geo_id) 
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [addrMechId, addr.get("address1"), addr.get("address2"), addr.get("city"), addr.get("province_code"), addr.get("zip"), addr.get("country_code")])
        
        execute_sql("""
            INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) 
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        """, [partyId, addrMechId, purpose])
```

---

## 3. Dry-Run / Sample JSON Analysis

Here we walk through how the sync logic executes against typical payloads in the `shopify-samples/customers-json/` folder.

### 3.1. Case A: Fully Populated Payload (`AllDetails - content.json`)
* **Payload Highlights**: Has full customer name (`Adam Smith`), primary email (`adam.smith@example.com`), primary phone (`+12127654321`), and one default address (`456 Park Avenue`).
* **Sync Trajectory**:
  1. The code queries `PartyIdentification` for `SHOPIFY_CUST_ID = '7194240516349'`.
  2. Assuming it's a new customer, it returns no match.
  3. It queries `PartyContactMech` for active email = `adam.smith@example.com`. No match.
  4. Creates a new `Party` and `Person` record for Adam Smith.
  5. Links external ID `7194240516349` in `PartyIdentification`.
  6. Creates a new `ContactMech` and `PartyContactMech` of type `EMAIL_ADDRESS` and purpose `PRIMARY_EMAIL` with `opt_in_ind = 'Y'` and `verified_ind = 'Y'`.
  7. Creates a new `ContactMech`, `TelecomNumber` and `PartyContactMech` of type `TELECOM_NUMBER` and purpose `PRIMARY_PHONE` for `+12127654321`.
  8. Iterates the addresses. Detects the address is default. Inserts a new `ContactMech`, `PostalAddress`, and `PartyContactMech` under purpose `SHIPPING_LOCATION`.

### 3.2. Case B: Missing Address Payload (`NoAddress - content.json` or address with empty lines)
* **Payload Highlights**: Has name, email, phone, but the address list has an element where `address1 = ""` and `zip = ""`.
* **Sync Trajectory**:
  1. Resolves/Creates the customer profile using name, email, and phone.
  2. Reaches the address sync iteration:
     - `addresses` list contains one item, but `addr.get("address1")` is empty (`""`).
     - The logic checks: `if not addr.get("address1") and not addr.get("zip"): continue`.
     - The address loop skips inserting records for this empty address.
  3. Correctly keeps the customer profile database records active with empty postal addresses, avoiding inserting junk/blank rows into the `PostalAddress` table.

### 3.3. Case C: Only Email Provided (`OnlyEmail - content.json`)
* **Payload Highlights**: Has name and email, but phone is `null`, and address array is empty (`[]`).
* **Sync Trajectory**:
  1. Resolves/Creates the customer profile.
  2. Synchronizes the email address contact mechanism.
  3. Skips phone number sync because `phone` is null/empty.
  4. Skips the address iteration loop entirely since `addresses` is empty.
  5. Correctly registers the customer with email only.
