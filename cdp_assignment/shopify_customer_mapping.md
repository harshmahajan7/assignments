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

## 2. Integration Implementation (Moqui XML Services)

The following XML snippet represents the integration layer constructed as a robust Moqui Service. It handles data translation, state checking, and transactional upserts for Shopify Customer payloads into the Universal Data Model.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<services xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://moqui.org/xsd/service-definition-3.xsd">

    <!-- ========================================== -->
    <!-- Service: Sync Shopify Customer Payload     -->
    <!-- ========================================== -->
    <service verb="sync" noun="ShopifyCustomer" authenticate="true">
        <description>
            Idempotent synchronization service for Shopify Customer Webhooks. 
            Performs UPSERT logic mapping Shopify JSON to UDM Party schema.
        </description>
        <in-parameters>
            <parameter name="shopifyCustomer" type="Map" required="true"/>
        </in-parameters>
        <actions>
            <!-- 1. Payload Validation -->
            <if condition="!shopifyCustomer || !shopifyCustomer.id">
                <return error="true" message="Payload validation failed: Missing required field 'id'."/>
            </if>
            <set field="shopifyIdStr" from="shopifyCustomer.id.toString()"/>

            <!-- 2. Idempotency Check (Locate Existing Customer) -->
            <entity-find-one entity-name="mantle.party.PartyIdentification" value-field="existingIdentity">
                <field-map field-name="partyIdTypeEnumId" value="SHOPIFY_CUST_ID"/>
                <field-map field-name="idValue" from="shopifyIdStr"/>
            </entity-find-one>

            <if condition="existingIdentity">
                <!-- ============================ -->
                <!-- UPDATE EXISTING PROFILE      -->
                <!-- ============================ -->
                <set field="partyId" from="existingIdentity.partyId"/>
                <log level="info" message="Updating existing customer [${partyId}] from Shopify ID: ${shopifyIdStr}"/>
                
                <service-call name="update#mantle.party.Person" 
                              in-map="[partyId: partyId, firstName: shopifyCustomer.first_name, lastName: shopifyCustomer.last_name]"/>
            <else>
                <!-- ============================ -->
                <!-- PROVISION NEW PROFILE        -->
                <!-- ============================ -->
                <log level="info" message="Provisioning new customer from Shopify ID: ${shopifyIdStr}"/>
                
                <service-call name="create#mantle.party.Party" in-map="[partyTypeEnumId: 'PtPerson']" out-map="partyOut"/>
                <set field="partyId" from="partyOut.partyId"/>
                
                <service-call name="create#mantle.party.Person" 
                              in-map="[partyId: partyId, firstName: shopifyCustomer.first_name, lastName: shopifyCustomer.last_name]"/>
                
                <!-- Bind Shopify Identity -->
                <service-call name="create#mantle.party.PartyIdentification" 
                              in-map="[partyId: partyId, partyIdTypeEnumId: 'SHOPIFY_CUST_ID', idValue: shopifyIdStr]"/>
                              
                <!-- Assign Customer Role -->
                <service-call name="create#mantle.party.PartyRole" in-map="[partyId: partyId, roleTypeId: 'Customer']"/>
            </else>
            </if>

            <!-- ============================ -->
            <!-- SYNCHRONIZE CONTACT INFO     -->
            <!-- ============================ -->

            <!-- Sync Email -->
            <if condition="shopifyCustomer.email">
                <!-- Check if this exact email is already linked and active -->
                <entity-find entity-name="mantle.party.contact.PartyContactMechInfo" list="existingEmails">
                    <econdition field-name="partyId" from="partyId"/>
                    <econdition field-name="contactMechTypeEnumId" value="CmtEmailAddress"/>
                    <econdition field-name="infoString" from="shopifyCustomer.email"/>
                    <date-filter/>
                </entity-find>

                <if condition="!existingEmails">
                    <!-- Translate Shopify booleans to UDM Indicators -->
                    <set field="verifiedInd" from="shopifyCustomer.verified_email ? 'Y' : 'N'"/>
                    <set field="optInInd" from="shopifyCustomer.accepts_marketing ? 'Y' : 'N'"/>
                    
                    <service-call name="create#mantle.party.contact.ContactMech" 
                                  in-map="[contactMechTypeEnumId: 'CmtEmailAddress', infoString: shopifyCustomer.email]" out-map="emailOut"/>
                                  
                    <service-call name="create#mantle.party.contact.PartyContactMech" 
                                  in-map="[partyId: partyId, contactMechId: emailOut.contactMechId, 
                                           contactMechPurposeId: 'EmailPrimary', fromDate: ec.user.nowTimestamp, 
                                           extension: optInInd]"/> <!-- Utilizing extension or custom field for opt-in based on schema -->
                </if>
            </if>

            <!-- Sync Phone -->
            <if condition="shopifyCustomer.phone">
                <!-- Check if exact phone is linked -->
                <entity-find entity-name="mantle.party.contact.PartyContactMechInfo" list="existingPhones">
                    <econdition field-name="partyId" from="partyId"/>
                    <econdition field-name="contactMechTypeEnumId" value="CmtTelecomNumber"/>
                    <econdition field-name="contactNumber" from="shopifyCustomer.phone"/>
                    <date-filter/>
                </entity-find>

                <if condition="!existingPhones">
                    <service-call name="create#mantle.party.contact.ContactMech" in-map="[contactMechTypeEnumId: 'CmtTelecomNumber']" out-map="phoneOut"/>
                    <service-call name="create#mantle.party.contact.TelecomNumber" in-map="[contactMechId: phoneOut.contactMechId, contactNumber: shopifyCustomer.phone]"/>
                    <service-call name="create#mantle.party.contact.PartyContactMech" 
                                  in-map="[partyId: partyId, contactMechId: phoneOut.contactMechId, 
                                           contactMechPurposeId: 'PhonePrimary', fromDate: ec.user.nowTimestamp]"/>
                </if>
            </if>

            <!-- Sync Address Array -->
            <if condition="shopifyCustomer.addresses &amp;&amp; shopifyCustomer.addresses.size() > 0">
                <iterate list="shopifyCustomer.addresses" entry="shopifyAddr">
                    <!-- Basic uniqueness check by address1 and zip -->
                    <entity-find entity-name="mantle.party.contact.PartyContactMechInfo" list="existingAddrs">
                        <econdition field-name="partyId" from="partyId"/>
                        <econdition field-name="contactMechTypeEnumId" value="CmtPostalAddress"/>
                        <econdition field-name="address1" from="shopifyAddr.address1"/>
                        <econdition field-name="postalCode" from="shopifyAddr.zip"/>
                        <date-filter/>
                    </entity-find>

                    <if condition="!existingAddrs">
                        <service-call name="create#mantle.party.contact.ContactMech" in-map="[contactMechTypeEnumId: 'CmtPostalAddress']" out-map="addrOut"/>
                        <service-call name="create#mantle.party.contact.PostalAddress" 
                            in-map="[contactMechId: addrOut.contactMechId, address1: shopifyAddr.address1, address2: shopifyAddr.address2, 
                                     city: shopifyAddr.city, provinceGeoId: shopifyAddr.province, postalCode: shopifyAddr.zip, 
                                     countryGeoId: shopifyAddr.country]"/>
                        
                        <!-- Map default attribute to Purpose -->
                        <set field="purposeId" from="shopifyAddr.default ? 'PostalShippingDest' : 'PostalGeneral'"/>
                        
                        <service-call name="create#mantle.party.contact.PartyContactMech" 
                                      in-map="[partyId: partyId, contactMechId: addrOut.contactMechId, 
                                               contactMechPurposeId: purposeId, fromDate: ec.user.nowTimestamp]"/>
                    </if>
                </iterate>
            </if>
            
            <log level="info" message="Synchronization complete for Shopify customer: ${shopifyIdStr}"/>
        </actions>
    </service>

</services>
```
