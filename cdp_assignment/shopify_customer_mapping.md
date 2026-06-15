# Shopify Customer Integration Mapping

This document describes the data mapping between the Shopify Customer API and the NotNaked UDM-based Customer Data Platform (CDP).

## 1. Field Mapping Table

| Shopify Customer API Field | UDM CDP Table | UDM CDP Column | Transformation / Notes |
| :--- | :--- | :--- | :--- |
| `id` | `PartyIdentification` | `id_value` | Stored with `party_id_type_enum_id` = 'SHOPIFY_CUST_ID' to prevent duplicate creation. |
| `first_name` | `Person` | `first_name` | Direct string mapping. |
| `last_name` | `Person` | `last_name` | Direct string mapping. |
| `email` | `ContactMech` | `info_string` | Created as `EMAIL_ADDRESS`. Linked via `PartyContactMech` as `PRIMARY_EMAIL`. |
| `verified_email` | `PartyContactMech` | `verified_ind` | Boolean mapped to 'Y' / 'N' on the Email's `PartyContactMech` record. |
| `phone` | `TelecomNumber` | `contact_number` | Created as `TELECOM_NUMBER`. Linked via `PartyContactMech` as `PRIMARY_PHONE`. Stripped of special chars if needed. |
| `accepts_marketing` | `PartyContactMech` | `opt_in_ind` | Boolean mapped to 'Y' / 'N' on the Email's `PartyContactMech` record. |

### Address Array Mapping

Shopify returns an array of `addresses`. Each object in the array is mapped to a `PostalAddress` in UDM:

| Shopify Address Field | UDM CDP Table | UDM CDP Column | Transformation / Notes |
| :--- | :--- | :--- | :--- |
| `address1` | `PostalAddress` | `address1` | Direct string mapping. |
| `address2` | `PostalAddress` | `address2` | Direct string mapping. |
| `city` | `PostalAddress` | `city` | Direct string mapping. |
| `province` | `PostalAddress` | `province_geo_id` | Can be mapped directly, or validated against a Geo dictionary. |
| `zip` | `PostalAddress` | `postal_code` | Direct string mapping. |
| `country` | `PostalAddress` | `country_geo_id` | Mapped to standard ISO Country Code if possible. |
| `phone` | `TelecomNumber` | `contact_number` | Handled as an additional `TELECOM_NUMBER` contact mech if different from the primary profile phone. |
| `default` | `PartyContactMech` | `contact_mech_purpose_enum_id` | If true, mapped as 'SHIPPING_LOCATION' and/or 'BILLING_LOCATION'. Otherwise 'GENERAL_LOCATION'. |

### Handling Data Type Differences
- **Booleans:** Shopify uses `true`/`false` booleans. The UDM database uses `CHAR(1)` ('Y'/'N') for indicator fields. The integration layer must translate these (e.g., `value ? 'Y' : 'N'`).
- **Multi-valued Fields:** Addresses are passed as arrays in Shopify. UDM handles this natively by creating multiple `ContactMech` and `PostalAddress` records, linking each back to the user via the `PartyContactMech` association table.

---

## 2. Integration Pseudo-code (Upsert Logic)

This pseudo-code demonstrates fetching data from Shopify, transforming it, and upserting it into the UDM database using Moqui XML Actions.

```xml
<service verb="sync" noun="ShopifyCustomer">
    <description>Integrates a Shopify Customer Payload into the UDM CDP.</description>
    <in-parameters>
        <parameter name="shopifyCustomer" type="Map" required="true"/>
    </in-parameters>
    <actions>
        <!-- 1. Data Validation -->
        <if condition="!shopifyCustomer || !shopifyCustomer.id">
            <return error="true" message="Invalid Shopify payload: Missing ID"/>
        </if>

        <set field="shopifyId" from="shopifyCustomer.id.toString()"/>

        <!-- 2. Check for existing customer using PartyIdentification (Upsert Logic) -->
        <entity-find-one entity-name="PartyIdentification" value-field="existingIdentity">
            <field-map field-name="partyIdTypeEnumId" value="SHOPIFY_CUST_ID"/>
            <field-map field-name="idValue" from="shopifyId"/>
        </entity-find-one>

        <if condition="existingIdentity">
            <!-- Customer exists -> UPDATE -->
            <set field="partyId" from="existingIdentity.partyId"/>
            <service-call name="update#Person" in-map="[partyId: partyId, firstName: shopifyCustomer.first_name, lastName: shopifyCustomer.last_name]"/>
            
            <else>
                <!-- Customer does not exist -> INSERT -->
                <service-call name="create#Party" in-map="[partyTypeEnumId: 'PERSON']" out-map="partyOut"/>
                <set field="partyId" from="partyOut.partyId"/>
                
                <service-call name="create#Person" in-map="[partyId: partyId, firstName: shopifyCustomer.first_name, lastName: shopifyCustomer.last_name]"/>
                
                <!-- Create Shopify ID linkage -->
                <service-call name="create#PartyIdentification" in-map="[partyId: partyId, partyIdTypeEnumId: 'SHOPIFY_CUST_ID', idValue: shopifyId]"/>
            </else>
        </if>

        <!-- Handle Contact Details -->
        
        <!-- Email -->
        <if condition="shopifyCustomer.email">
            <!-- Assume logic to expire old emails exists here -->
            <service-call name="create#ContactMech" in-map="[contactMechTypeEnumId: 'EMAIL_ADDRESS', infoString: shopifyCustomer.email]" out-map="emailOut"/>
            <service-call name="create#PartyContactMech" 
                in-map="[partyId: partyId, contactMechId: emailOut.contactMechId, contactMechPurposeEnumId: 'PRIMARY_EMAIL', fromDate: ec.user.nowTimestamp, verifiedInd: shopifyCustomer.verified_email ? 'Y' : 'N', optInInd: shopifyCustomer.accepts_marketing ? 'Y' : 'N']"/>
        </if>

        <!-- Phone -->
        <if condition="shopifyCustomer.phone">
            <service-call name="create#ContactMech" in-map="[contactMechTypeEnumId: 'TELECOM_NUMBER']" out-map="phoneOut"/>
            <service-call name="create#TelecomNumber" in-map="[contactMechId: phoneOut.contactMechId, contactNumber: shopifyCustomer.phone]"/>
            <service-call name="create#PartyContactMech" 
                in-map="[partyId: partyId, contactMechId: phoneOut.contactMechId, contactMechPurposeEnumId: 'PRIMARY_PHONE', fromDate: ec.user.nowTimestamp]"/>
        </if>

        <!-- Addresses Array -->
        <if condition="shopifyCustomer.addresses">
            <iterate list="shopifyCustomer.addresses" entry="shopifyAddr">
                <service-call name="create#ContactMech" in-map="[contactMechTypeEnumId: 'POSTAL_ADDRESS']" out-map="addrOut"/>
                <service-call name="create#PostalAddress" 
                    in-map="[contactMechId: addrOut.contactMechId, address1: shopifyAddr.address1, address2: shopifyAddr.address2, city: shopifyAddr.city, provinceGeoId: shopifyAddr.province, postalCode: shopifyAddr.zip, countryGeoId: shopifyAddr.country]"/>
                
                <!-- Map default attribute to Purpose -->
                <set field="purpose" from="shopifyAddr.default ? 'SHIPPING_LOCATION' : 'GENERAL_LOCATION'"/>
                
                <service-call name="create#PartyContactMech" 
                    in-map="[partyId: partyId, contactMechId: addrOut.contactMechId, contactMechPurposeEnumId: purpose, fromDate: ec.user.nowTimestamp]"/>
            </iterate>
        </if>
        
        <log message="Successfully synced Shopify customer: ${shopifyId}"/>
    </actions>
</service>
```
