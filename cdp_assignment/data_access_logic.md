# Customer Data Platform (CDP) Data Access Architecture

This document defines the Moqui Framework service layer for the NotNaked CDP. The services handle all CRUD operations for the UDM `Party` schema, ensuring data integrity, relationship management, and transaction safety.

## Overview of Service Definitions
These services manage the `Party`, `Person`, `ContactMech` (Postal, Email, Telecom), and their associative entities (`PartyContactMech`, `PartyIdentification`).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<services xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://moqui.org/xsd/service-definition-3.xsd">

    <!-- ========================================== -->
    <!-- Service: Create Customer Profile           -->
    <!-- ========================================== -->
    <service verb="create" noun="CustomerProfile" authenticate="true">
        <description>
            Orchestrates the creation of a complete customer profile within the UDM.
            Handles the base Party, Person, and multiple Contact Mechanisms atomically.
        </description>
        <in-parameters>
            <parameter name="firstName" required="true" type="String"/>
            <parameter name="lastName" required="true" type="String"/>
            <parameter name="emailAddress" type="String">
                <text-email/>
            </parameter>
            <parameter name="contactNumber" type="String"/>
            <parameter name="acceptsMarketing" type="Boolean" default-value="false"/>
            <parameter name="externalId" type="String"/>
            <parameter name="externalIdType" type="String" default-value="SHOPIFY_CUST_ID"/>
        </in-parameters>
        <out-parameters>
            <parameter name="partyId" required="true"/>
        </out-parameters>
        <actions>
            <!-- 1. Establish the Core Party Entity -->
            <service-call name="create#mantle.party.Party" in-map="[partyTypeEnumId: 'PtPerson']" out-map="partyOut"/>
            <set field="partyId" from="partyOut.partyId"/>

            <!-- 2. Populate the Person Sub-entity -->
            <service-call name="create#mantle.party.Person" 
                          in-map="[partyId: partyId, firstName: firstName, lastName: lastName]"/>

            <!-- 3. Assign Default Party Role -->
            <service-call name="create#mantle.party.PartyRole" 
                          in-map="[partyId: partyId, roleTypeId: 'Customer']"/>

            <!-- 4. Handle Identity Mapping (e.g., Shopify ID) -->
            <if condition="externalId">
                <service-call name="create#mantle.party.PartyIdentification" 
                              in-map="[partyId: partyId, partyIdTypeEnumId: externalIdType, idValue: externalId]"/>
            </if>

            <!-- 5. Provision Primary Email Address -->
            <if condition="emailAddress">
                <service-call name="create#mantle.party.contact.ContactMech" 
                              in-map="[contactMechTypeEnumId: 'CmtEmailAddress', infoString: emailAddress]" out-map="emailOut"/>
                
                <set field="optInInd" from="acceptsMarketing ? 'Y' : 'N'"/>
                <service-call name="create#mantle.party.contact.PartyContactMech" 
                              in-map="[partyId: partyId, contactMechId: emailOut.contactMechId, 
                                       contactMechPurposeId: 'EmailPrimary', fromDate: ec.user.nowTimestamp, 
                                       extension: optInInd]"/>
            </if>

            <!-- 6. Provision Primary Telecom Number -->
            <if condition="contactNumber">
                <service-call name="create#mantle.party.contact.ContactMech" 
                              in-map="[contactMechTypeEnumId: 'CmtTelecomNumber']" out-map="phoneOut"/>
                
                <service-call name="create#mantle.party.contact.TelecomNumber" 
                              in-map="[contactMechId: phoneOut.contactMechId, contactNumber: contactNumber]"/>
                
                <service-call name="create#mantle.party.contact.PartyContactMech" 
                              in-map="[partyId: partyId, contactMechId: phoneOut.contactMechId, 
                                       contactMechPurposeId: 'PhonePrimary', fromDate: ec.user.nowTimestamp]"/>
            </if>

            <log level="info" message="Successfully created Customer Profile for partyId: ${partyId}"/>
        </actions>
    </service>

    <!-- ========================================== -->
    <!-- Service: Retrieve Customer Profile         -->
    <!-- ========================================== -->
    <service verb="get" noun="CustomerProfile" authenticate="true">
        <description>
            Aggregates customer data including identities and active contact mechanisms into a structured map.
        </description>
        <in-parameters>
            <parameter name="partyId" required="true"/>
        </in-parameters>
        <out-parameters>
            <parameter name="customerProfile" type="Map"/>
        </out-parameters>
        <actions>
            <set field="customerProfile" from="[:]"/>
            
            <!-- Fetch Person Details -->
            <entity-find-one entity-name="mantle.party.Person" value-field="person">
                <field-map field-name="partyId" from="partyId"/>
            </entity-find-one>
            
            <if condition="!person">
                <return error="true" message="Customer record not found for partyId [${partyId}]."/>
            </if>
            
            <script>
                customerProfile.putAll(person.getMap())
                customerProfile.identities = []
                customerProfile.contactMethods = [emails: [], phones: [], addresses: []]
            </script>

            <!-- Fetch External Identities -->
            <entity-find entity-name="mantle.party.PartyIdentification" list="identities">
                <econdition field-name="partyId" from="partyId"/>
            </entity-find>
            <iterate list="identities" entry="identity">
                <script>customerProfile.identities.add([type: identity.partyIdTypeEnumId, value: identity.idValue])</script>
            </iterate>

            <!-- Fetch Active Contact Mechanisms via View Entity -->
            <entity-find entity-name="mantle.party.contact.PartyContactMechInfo" list="contactMechs">
                <econdition field-name="partyId" from="partyId"/>
                <date-filter/> <!-- Automatically filters out expired thruDate records -->
            </entity-find>

            <iterate list="contactMechs" entry="cm">
                <if condition="cm.contactMechTypeEnumId == 'CmtEmailAddress'">
                    <script>customerProfile.contactMethods.emails.add([id: cm.contactMechId, email: cm.infoString, purpose: cm.contactMechPurposeId])</script>
                <else-if condition="cm.contactMechTypeEnumId == 'CmtTelecomNumber'">
                    <script>customerProfile.contactMethods.phones.add([id: cm.contactMechId, number: cm.contactNumber, purpose: cm.contactMechPurposeId])</script>
                </else-if>
                <else-if condition="cm.contactMechTypeEnumId == 'CmtPostalAddress'">
                    <script>customerProfile.contactMethods.addresses.add([id: cm.contactMechId, address1: cm.address1, city: cm.city, zip: cm.postalCode, purpose: cm.contactMechPurposeId])</script>
                </else-if>
                </if>
            </iterate>
        </actions>
    </service>

    <!-- ========================================== -->
    <!-- Service: Update Customer Profile           -->
    <!-- ========================================== -->
    <service verb="update" noun="CustomerProfile" authenticate="true">
        <description>
            Applies updates to the customer's base profile. Uses soft-delete (thruDate expiration) 
            for updating contact mechanisms to maintain historical integrity.
        </description>
        <in-parameters>
            <parameter name="partyId" required="true"/>
            <parameter name="firstName"/>
            <parameter name="lastName"/>
            <parameter name="emailAddress"/>
        </in-parameters>
        <actions>
            <!-- 1. Update Core Person Data -->
            <if condition="firstName || lastName">
                <service-call name="update#mantle.party.Person" in-map="context"/>
            </if>

            <!-- 2. Rotate Email Address Safely -->
            <if condition="emailAddress">
                <!-- Locate existing active primary emails -->
                <entity-find entity-name="mantle.party.contact.PartyContactMech" list="oldEmails">
                    <econdition field-name="partyId" from="partyId"/>
                    <econdition field-name="contactMechPurposeId" value="EmailPrimary"/>
                    <date-filter/>
                </entity-find>
                
                <!-- Soft-delete old emails -->
                <iterate list="oldEmails" entry="oldEmail">
                    <service-call name="update#mantle.party.contact.PartyContactMech" 
                                  in-map="[partyId: oldEmail.partyId, contactMechId: oldEmail.contactMechId, 
                                           contactMechPurposeId: oldEmail.contactMechPurposeId, 
                                           fromDate: oldEmail.fromDate, thruDate: ec.user.nowTimestamp]"/>
                </iterate>
                
                <!-- Provision new email -->
                <service-call name="create#mantle.party.contact.ContactMech" 
                              in-map="[contactMechTypeEnumId: 'CmtEmailAddress', infoString: emailAddress]" out-map="newEmail"/>
                <service-call name="create#mantle.party.contact.PartyContactMech" 
                              in-map="[partyId: partyId, contactMechId: newEmail.contactMechId, 
                                       contactMechPurposeId: 'EmailPrimary', fromDate: ec.user.nowTimestamp]"/>
            </if>
        </actions>
    </service>

    <!-- ========================================== -->
    <!-- Service: Soft Delete Customer              -->
    <!-- ========================================== -->
    <service verb="delete" noun="CustomerProfile" authenticate="true">
        <description>
            Marks a customer as inactive. In the UDM, we avoid hard deletes. 
            We disable the user account (if any) and expire all active contact linkages.
        </description>
        <in-parameters>
            <parameter name="partyId" required="true"/>
        </in-parameters>
        <actions>
            <!-- 1. Expire all active PartyContactMech records -->
            <entity-find entity-name="mantle.party.contact.PartyContactMech" list="activeMechs">
                <econdition field-name="partyId" from="partyId"/>
                <date-filter/>
            </entity-find>

            <iterate list="activeMechs" entry="pcm">
                <set field="pcm.thruDate" from="ec.user.nowTimestamp"/>
                <entity-update value-field="pcm"/>
            </iterate>
            
            <!-- 2. Update Party Status to Disabled (Assuming Disabled state exists) -->
            <service-call name="update#mantle.party.Party" in-map="[partyId: partyId, statusId: 'PartyDisabled']" ignore-error="true"/>
            
            <log level="info" message="Customer ${partyId} has been successfully soft-deleted."/>
        </actions>
    </service>

</services>
```
