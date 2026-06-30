# Data Access Logic & Shopify Integration Pseudo-code

This document describes the logic for accessing, manipulating, and integrating customer data within the Customer Data Platform (CDP) for NotNaked. It provides both structural pseudo-code (written in Groovy) and concrete Moqui Framework XML service patterns.

---

## 1. CDP Customer CRUD Operations

### 1.1. Create Customer Profile
This operation creates a new customer, registers their basic details, and initializes their primary contact mechanisms.

#### Pseudo-code (Groovy):
```groovy
String createCustomerProfile(String firstName, String lastName, String emailAddress, String contactNumber, Boolean acceptsMarketing, String externalId) {
    // 1. Validation
    if (!firstName || !lastName) {
        throw new ValidationError("First name and last name are required.")
    }
    
    if (emailAddress && !isValidEmail(emailAddress)) {
        throw new ValidationError("Invalid email address format.")
    }

    // Start Transaction
    beginTransaction()
    try {
        // 2. Create base Party
        String partyId = generateUUID()
        executeSql(
            "INSERT INTO Party (party_id, party_type_enum_id) VALUES (?, 'PERSON')", 
            [partyId]
        )
        
        // 3. Create Person subtype
        executeSql(
            "INSERT INTO Person (party_id, first_name, last_name) VALUES (?, ?, ?)", 
            [partyId, firstName, lastName]
        )

        // 4. Associate External ID (e.g. Shopify ID) if provided
        if (externalId) {
            executeSql(
                "INSERT INTO PartyIdentification (party_id, party_id_type_enum_id, id_value) VALUES (?, 'SHOPIFY_CUST_ID', ?)", 
                [partyId, externalId]
            )
        }

        // 5. Create primary Email ContactMech
        if (emailAddress) {
            String emailMechId = generateUUID()
            executeSql(
                "INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) VALUES (?, 'EMAIL_ADDRESS', ?)", 
                [emailMechId, emailAddress]
            )
            String optInVal = acceptsMarketing ? 'Y' : 'N'
            executeSql(
                "INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date, opt_in_ind) VALUES (?, ?, 'PRIMARY_EMAIL', CURRENT_TIMESTAMP, ?)", 
                [partyId, emailMechId, optInVal]
            )
        }

        // 6. Create primary Phone ContactMech
        if (contactNumber) {
            String phoneMechId = generateUUID()
            executeSql(
                "INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'TELECOM_NUMBER')", 
                [phoneMechId]
            )
            executeSql(
                "INSERT INTO TelecomNumber (contact_mech_id, contact_number) VALUES (?, ?)", 
                [phoneMechId, contactNumber]
            )
            executeSql(
                "INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES (?, ?, 'PRIMARY_PHONE', CURRENT_TIMESTAMP)", 
                [partyId, phoneMechId]
            )
        }

        commitTransaction()
        return partyId

    } catch (DatabaseException e) {
        rollbackTransaction()
        throw new SystemError("Failed to create customer: " + e.getMessage())
    }
}
```

---

### 1.2. Retrieve Customer Profile
Retrieves a customer's basic details, external identities, active contact methods (emails, phones, postal addresses), and preferences.

#### Pseudo-code (Groovy):
```groovy
Map retrieveCustomerProfile(String partyId) {
    // 1. Retrieve Person Details
    def person = executeSql("SELECT first_name, last_name, date_of_birth FROM Person WHERE party_id = ?", [partyId]).first()
    if (!person) {
        throw new NotFoundError("No customer found for ID: " + partyId)
    }
        
    Map profile = [
        partyId: partyId,
        firstName: person.first_name,
        lastName: person.last_name,
        dateOfBirth: person.date_of_birth,
        identities: [],
        emails: [],
        phones: [],
        addresses: [],
        preferences: [:]
    ]

    // 2. Retrieve External Identities
    def identities = executeSql("SELECT party_id_type_enum_id, id_value FROM PartyIdentification WHERE party_id = ?", [partyId])
    for (ident in identities) {
        profile.identities.add([
            type: ident.party_id_type_enum_id,
            value: ident.id_value
        ])
    }

    // 3. Retrieve Active Contact Mechanisms
    def contactMechs = executeSql("""
        SELECT cm.contact_mech_id, cm.contact_mech_type_enum_id, cm.info_string, pcm.contact_mech_purpose_enum_id, pcm.opt_in_ind, pcm.verified_ind
        FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        WHERE pcm.party_id = ? AND (pcm.thru_date IS NULL OR pcm.thru_date > CURRENT_TIMESTAMP)
    """, [partyId])

    for (cm in contactMechs) {
        if (cm.contact_mech_type_enum_id == 'EMAIL_ADDRESS') {
            profile.emails.add([
                contactMechId: cm.contact_mech_id,
                email: cm.info_string,
                purpose: cm.contact_mech_purpose_enum_id,
                acceptsMarketing: cm.opt_in_ind == 'Y',
                verified: cm.verified_ind == 'Y'
            ])
            
        } else if (cm.contact_mech_type_enum_id == 'TELECOM_NUMBER') {
            def phone = executeSql("SELECT country_code, area_code, contact_number FROM TelecomNumber WHERE contact_mech_id = ?", [cm.contact_mech_id]).first()
            profile.phones.add([
                contactMechId: cm.contact_mech_id,
                phoneNumber: phone.contact_number,
                purpose: cm.contact_mech_purpose_enum_id
            ])

        } else if (cm.contact_mech_type_enum_id == 'POSTAL_ADDRESS') {
            def addr = executeSql("SELECT address1, address2, city, province_geo_id, postal_code, country_geo_id FROM PostalAddress WHERE contact_mech_id = ?", [cm.contact_mech_id]).first()
            profile.addresses.add([
                contactMechId: cm.contact_mech_id,
                address1: addr.address1,
                address2: addr.address2,
                city: addr.city,
                province: addr.province_geo_id,
                zip: addr.postal_code,
                country: addr.country_geo_id,
                purpose: cm.contact_mech_purpose_enum_id
            ])
        }
    }

    // 4. Retrieve Customer Preferences
    def preferences = executeSql("SELECT preference_key, preference_value FROM CustomerPreference WHERE party_id = ?", [partyId])
    for (pref in preferences) {
        profile.preferences[pref.preference_key] = pref.preference_value
    }

    return profile
}
```

---

### 1.3. Update Customer Profile
Updates a customer's basic details and handles contact method changes. To preserve audit history, existing contact mechanisms are expired (soft-modified), and new ones are inserted.

#### Pseudo-code (Groovy):
```groovy
void updateCustomerProfile(String partyId, String firstName, String lastName, String emailAddress, Map addressUpdate) {
    beginTransaction()
    try {
        // 1. Update basic Person info
        if (firstName || lastName) {
            Map updateFields = [:]
            if (firstName) updateFields["first_name"] = firstName
            if (lastName) updateFields["last_name"] = lastName
            
            String setClause = updateFields.keySet().collect { "$it = ?" }.join(", ")
            List params = updateFields.values().toList() + [partyId]
            executeSql("UPDATE Person SET $setClause WHERE party_id = ?", params)
        }

        // 2. Update Primary Email (expire old, insert new if changed)
        if (emailAddress) {
            def currentEmail = executeSql("""
                SELECT cm.contact_mech_id, cm.info_string, pcm.from_date
                FROM PartyContactMech pcm
                JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
                WHERE pcm.party_id = ? AND pcm.contact_mech_purpose_enum_id = 'PRIMARY_EMAIL' AND pcm.thru_date IS NULL
            """, [partyId]).first()

            if (!currentEmail || currentEmail.info_string != emailAddress) {
                if (currentEmail) {
                    // Expire old email relationship
                    executeSql(
                        "UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP WHERE party_id = ? AND contact_mech_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_EMAIL' AND from_date = ?", 
                        [partyId, currentEmail.contact_mech_id, currentEmail.from_date]
                    )
                }
                
                // Insert new email contact mech
                String newEmailMechId = generateUUID()
                executeSql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) VALUES (?, 'EMAIL_ADDRESS', ?)", [newEmailMechId, emailAddress])
                executeSql("INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES (?, ?, 'PRIMARY_EMAIL', CURRENT_TIMESTAMP)", [partyId, newEmailMechId])
            }
        }

        // 3. Update Addresses (e.g., Shipping Address)
        if (addressUpdate) {
            // Expire active Shipping address
            def currentAddr = executeSql("""
                SELECT contact_mech_id, from_date FROM PartyContactMech 
                WHERE party_id = ? AND contact_mech_purpose_enum_id = 'SHIPPING_LOCATION' AND thru_date IS NULL
            """, [partyId]).first()
            
            if (currentAddr) {
                executeSql(
                    "UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP WHERE party_id = ? AND contact_mech_id = ? AND contact_mech_purpose_enum_id = 'SHIPPING_LOCATION' AND from_date = ?", 
                    [partyId, currentAddr.contact_mech_id, currentAddr.from_date]
                )
            }

            // Insert new Postal Address
            String newAddrMechId = generateUUID()
            executeSql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'POSTAL_ADDRESS')", [newAddrMechId])
            executeSql("""
                INSERT INTO PostalAddress (contact_mech_id, address1, address2, city, province_geo_id, postal_code, country_geo_id) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [newAddrMechId, addressUpdate.address1, addressUpdate.address2, addressUpdate.city, addressUpdate.province, addressUpdate.zip, addressUpdate.country])
            
            executeSql("INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) VALUES (?, ?, 'SHIPPING_LOCATION', CURRENT_TIMESTAMP)", [partyId, newAddrMechId])
        }

        commitTransaction()
    } catch (Exception e) {
        rollbackTransaction()
        throw new SystemError("Profile update failed: " + e.getMessage())
    }
}
```

---

### 1.4. Soft Delete Customer Profile
**Implications of Hard Deletes**: A hard delete (`DELETE FROM Party WHERE party_id = ...`) is highly discouraged in a CDP. It violates database referential integrity by breaking foreign keys associated with historical tables (e.g., Order headers, payments, customer service tickets) or forces cascading deletions that erase valuable business records.
**Soft Delete Strategy**:
1. Expire all contact mechanisms by setting their `thru_date` to `CURRENT_TIMESTAMP`. This immediately removes them from active lists.
2. Disable the customer record in the `Party` table (using a status field like `party_type_enum_id` or a status code) to prevent future transactions while preserving the ID and details for analytics/reporting.

#### Pseudo-code (Groovy):
```groovy
Boolean softDeleteCustomerProfile(String partyId) {
    beginTransaction()
    try {
        // 1. Expire all active contact mechanisms
        executeSql(
            "UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP WHERE party_id = ? AND (thru_date IS NULL OR thru_date > CURRENT_TIMESTAMP)", 
            [partyId]
        )

        // 2. Mark the Party as disabled / inactive
        // In Moqui, this is typically done by setting statusId = 'PartyDisabled'
        executeSql(
            "UPDATE Party SET party_type_enum_id = 'DISABLED_PERSON' WHERE party_id = ?", 
            [partyId]
        )

        commitTransaction()
        return true
    } catch (Exception e) {
        rollbackTransaction()
        throw new SystemError("Soft delete failed: " + e.getMessage())
    }
}
```

---

## 2. Shopify Customer Integration Logic

This section outlines the process of retrieving data from Shopify, transforming it, and storing/upserting it into the UDM.

### 2.1. Retrieve Customer Data from Shopify Customer API
Handles API requests, rate limiting (HTTP 429), and pagination using the standard HTTP `Link` header.

#### Pseudo-code (Groovy / Java):
```groovy
import groovy.json.JsonSlurper
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

List fetchShopifyCustomers(String shopUrl, String apiToken, Integer limit = 50) {
    String url = "https://${shopUrl}/admin/api/2024-01/customers.json?limit=${limit}"
    HttpClient client = HttpClient.newHttpClient()
    List allCustomers = []

    while (url) {
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(url))
            .header("X-Shopify-Access-Token", apiToken)
            .header("Content-Type", "application/json")
            .GET()
            .build()

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString())

        // Handle Rate Limiting (429 Too Many Requests)
        if (response.statusCode() == 429) {
            String retryAfterHeader = response.headers().firstValue("Retry-After").orElse("2")
            Integer retryAfter = Integer.parseInt(retryAfterHeader)
            Thread.sleep(retryAfter * 1000)
            continue
        }

        if (response.statusCode() != 200) {
            throw new Exception("Shopify API Error: " + response.statusCode() + " - " + response.body())
        }

        def data = new JsonSlurper().parseText(response.body())
        allCustomers.addAll(data.customers)

        // Handle Pagination via Link Header
        String linkHeader = response.headers().firstValue("Link").orElse(null)
        url = null
        if (linkHeader) {
            List links = linkHeader.split(",")
            for (link in links) {
                if (link.contains('rel="next"')) {
                    url = link.split(";")[0].trim().replace("<", "").replace(">", "")
                }
            }
        }
    }
    return allCustomers
}
```

---

### 2.2. Transformed Store / Upsert Customer (Shopify Sync)
Implements robust conflict and duplicate resolution during data sync.

#### Duplicate / Conflict Resolution Rules:
1. **Search by external ID**: Check if a record exists in `PartyIdentification` where `party_id_type_enum_id = 'SHOPIFY_CUST_ID'` and `id_value = shopify_customer_id`. If found, we update that Party.
2. **Search by Email**: If no Shopify ID match is found, check if a party already exists in the system with the exact primary email address. If found, we "link" the Shopify customer to this existing Party ID by inserting a new `PartyIdentification` record. This merges the profiles and prevents duplicate entries for the same person.
3. **Insert New**: If neither matches, create a brand-new Party and Person.

#### Pseudo-code (Groovy):
```groovy
String syncShopifyCustomer(Map shopifyCustomerPayload) {
    Map shopifyCust = shopifyCustomerPayload.customer
    if (!shopifyCust || !shopifyCust.id) {
        throw new IllegalArgumentException("Payload missing required customer ID")
    }

    String shopifyId = shopifyCust.id.toString()
    String email = shopifyCust.email
    String phone = shopifyCust.phone

    beginTransaction()
    try {
        String partyId = null

        // Rule 1: Find by Shopify ID
        def existingIdent = executeSql("""
            SELECT party_id FROM PartyIdentification 
            WHERE party_id_type_enum_id = 'SHOPIFY_CUST_ID' AND id_value = ?
        """, [shopifyId]).first()

        if (existingIdent) {
            partyId = existingIdent.party_id
            // Update Person basic info
            executeSql("""
                UPDATE Person SET first_name = ?, last_name = ? 
                WHERE party_id = ?
            """, [shopifyCust.first_name, shopifyCust.last_name, partyId])
        } else {
            // Rule 2: Find by Email
            if (email) {
                def existingEmail = executeSql("""
                    SELECT pcm.party_id 
                    FROM PartyContactMech pcm
                    JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
                    WHERE cm.contact_mech_type_enum_id = 'EMAIL_ADDRESS' AND cm.info_string = ? AND pcm.thru_date IS NULL
                """, [email]).first()
                if (existingEmail) {
                    partyId = existingEmail.party_id
                }
            }
            
            // Rule 3: Insert new Party if not found
            if (!partyId) {
                partyId = generateUUID()
                executeSql("INSERT INTO Party (party_id, party_type_enum_id) VALUES (?, 'PERSON')", [partyId])
                executeSql("INSERT INTO Person (party_id, first_name, last_name) VALUES (?, ?, ?)", [partyId, shopifyCust.first_name, shopifyCust.last_name])
                executeSql("INSERT INTO PartyRole (party_id, role_type_id) VALUES (?, 'Customer')", [partyId])
            }
            
            // Create/link Shopify ID identity
            executeSql("""
                INSERT INTO PartyIdentification (party_id, party_id_type_enum_id, id_value) 
                VALUES (?, 'SHOPIFY_CUST_ID', ?)
            """, [partyId, shopifyId])
        }

        // Sync Email Address
        if (email) {
            syncEmailContactMech(partyId, email, shopifyCust.verified_email, shopifyCust.accepts_marketing)
        }

        // Sync Phone Number
        if (phone) {
            syncPhoneContactMech(partyId, phone)
        }

        // Sync Addresses list
        List addresses = shopifyCust.addresses ?: []
        for (addr in addresses) {
            // Skip addresses with empty structural data
            if (!addr.address1 && !addr.zip) {
                continue
            }
            syncAddressContactMech(partyId, addr)
        }

        commitTransaction()
        return partyId
    } catch (Exception e) {
        rollbackTransaction()
        throw new SystemError("Shopify customer sync failed: " + e.getMessage())
    }
}

void syncEmailContactMech(String partyId, String email, Boolean verified, Boolean acceptsMarketing) {
    // Check if this email is already active for this customer
    def existing = executeSql("""
        SELECT cm.contact_mech_id FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        WHERE pcm.party_id = ? AND cm.contact_mech_type_enum_id = 'EMAIL_ADDRESS' AND cm.info_string = ? AND pcm.thru_date IS NULL
    """, [partyId, email]).first()

    String optInInd = acceptsMarketing ? 'Y' : 'N'
    String verifiedInd = verified ? 'Y' : 'N'

    if (!existing) {
        // Expire older primary emails if they exist
        executeSql("""
            UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP 
            WHERE party_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_EMAIL' AND thru_date IS NULL
        """, [partyId])

        String emailMechId = generateUUID()
        executeSql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id, info_string) VALUES (?, 'EMAIL_ADDRESS', ?)", [emailMechId, email])
        executeSql("""
            INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date, opt_in_ind, verified_ind) 
            VALUES (?, ?, 'PRIMARY_EMAIL', CURRENT_TIMESTAMP, ?, ?)
        """, [partyId, emailMechId, optInInd, verifiedInd])
    } else {
        // Update marketing preference and verification status on current email
        executeSql("""
            UPDATE PartyContactMech SET opt_in_ind = ?, verified_ind = ? 
            WHERE party_id = ? AND contact_mech_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_EMAIL'
        """, [optInInd, verifiedInd, partyId, existing.contact_mech_id])
    }
}

void syncPhoneContactMech(String partyId, String phone) {
    def existing = executeSql("""
        SELECT cm.contact_mech_id FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        JOIN TelecomNumber tn ON cm.contact_mech_id = tn.contact_mech_id
        WHERE pcm.party_id = ? AND cm.contact_mech_type_enum_id = 'TELECOM_NUMBER' AND tn.contact_number = ? AND pcm.thru_date IS NULL
    """, [partyId, phone]).first()

    if (!existing) {
        // Expire older primary phones
        executeSql("""
            UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP 
            WHERE party_id = ? AND contact_mech_purpose_enum_id = 'PRIMARY_PHONE' AND thru_date IS NULL
        """, [partyId])

        String phoneMechId = generateUUID()
        executeSql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'TELECOM_NUMBER')", [phoneMechId])
        executeSql("INSERT INTO TelecomNumber (contact_mech_id, contact_number) VALUES (?, ?)", [phoneMechId, phone])
        executeSql("""
            INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) 
            VALUES (?, ?, 'PRIMARY_PHONE', CURRENT_TIMESTAMP)
        """, [partyId, phoneMechId])
    }
}

void syncAddressContactMech(String partyId, Map addr) {
    // Check if address already registered and active
    def existing = executeSql("""
        SELECT cm.contact_mech_id FROM PartyContactMech pcm
        JOIN ContactMech cm ON pcm.contact_mech_id = cm.contact_mech_id
        JOIN PostalAddress pa ON cm.contact_mech_id = pa.contact_mech_id
        WHERE pcm.party_id = ? AND cm.contact_mech_type_enum_id = 'POSTAL_ADDRESS' 
          AND pa.address1 = ? AND pa.postal_code = ? AND pcm.thru_date IS NULL
    """, [partyId, addr.address1, addr.zip]).first()

    String purpose = addr.default ? 'SHIPPING_LOCATION' : 'POSTAL_ADDRESS'

    if (!existing) {
        // If it's a new default address, expire old SHIPPING_LOCATION address
        if (addr.default) {
            executeSql("""
                UPDATE PartyContactMech SET thru_date = CURRENT_TIMESTAMP 
                WHERE party_id = ? AND contact_mech_purpose_enum_id = 'SHIPPING_LOCATION' AND thru_date IS NULL
            """, [partyId])
        }

        String addrMechId = generateUUID()
        executeSql("INSERT INTO ContactMech (contact_mech_id, contact_mech_type_enum_id) VALUES (?, 'POSTAL_ADDRESS')", [addrMechId])
        executeSql("""
            INSERT INTO PostalAddress (contact_mech_id, address1, address2, city, province_geo_id, postal_code, country_geo_id) 
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [addrMechId, addr.address1, addr.address2, addr.city, addr.province_code, addr.zip, addr.country_code])
        
        executeSql("""
            INSERT INTO PartyContactMech (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date) 
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        """, [partyId, addrMechId, purpose])
    }
}
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
     - `addresses` list contains one item, but `addr.address1` is empty (`""`).
     - The logic checks: `if (!addr.address1 && !addr.zip) continue`.
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
