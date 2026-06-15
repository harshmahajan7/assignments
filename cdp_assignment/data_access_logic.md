# Data Access Logic (Moqui XML Actions)

This document provides the data access and manipulation logic for the NotNaked Customer Data Platform (CDP) using Moqui XML Actions.

## 1. Create a New Customer Record

```xml
<service verb="create" noun="Customer">
    <description>Creates a new customer record (Party, Person, ContactMechs)</description>
    <in-parameters>
        <parameter name="firstName" required="true"/>
        <parameter name="lastName" required="true"/>
        <parameter name="emailAddress"/>
        <parameter name="contactNumber"/>
        <parameter name="acceptsMarketing" type="Boolean" default-value="false"/>
    </in-parameters>
    <out-parameters>
        <parameter name="partyId"/>
    </out-parameters>
    <actions>
        <!-- 1. Validate Input Data -->
        <if condition="!emailAddress &amp;&amp; !contactNumber">
            <return error="true" message="At least one contact method (email or phone) is required."/>
        </if>

        <!-- 2. Create Base Party and Person Records -->
        <service-call name="create#Party" in-map="[partyTypeEnumId: 'PERSON']" out-map="partyOut"/>
        <set field="partyId" from="partyOut.partyId"/>

        <service-call name="create#Person" in-map="[partyId: partyId, firstName: firstName, lastName: lastName]"/>

        <!-- 3. Handle Email Address -->
        <if condition="emailAddress">
            <!-- Create ContactMech -->
            <service-call name="create#ContactMech" in-map="[contactMechTypeEnumId: 'EMAIL_ADDRESS', infoString: emailAddress]" out-map="emailOut"/>
            
            <!-- Link via PartyContactMech -->
            <service-call name="create#PartyContactMech" 
                in-map="[partyId: partyId, contactMechId: emailOut.contactMechId, contactMechPurposeEnumId: 'PRIMARY_EMAIL', fromDate: ec.user.nowTimestamp, optInInd: acceptsMarketing ? 'Y' : 'N']"/>
        </if>

        <!-- 4. Handle Phone Number -->
        <if condition="contactNumber">
            <!-- Create ContactMech and TelecomNumber -->
            <service-call name="create#ContactMech" in-map="[contactMechTypeEnumId: 'TELECOM_NUMBER']" out-map="phoneOut"/>
            <service-call name="create#TelecomNumber" in-map="[contactMechId: phoneOut.contactMechId, contactNumber: contactNumber]"/>
            
            <!-- Link via PartyContactMech -->
            <service-call name="create#PartyContactMech" 
                in-map="[partyId: partyId, contactMechId: phoneOut.contactMechId, contactMechPurposeEnumId: 'PRIMARY_PHONE', fromDate: ec.user.nowTimestamp]"/>
        </if>
    </actions>
</service>
```

## 2. Retrieve a Customer Record

```xml
<service verb="get" noun="Customer">
    <description>Retrieves a customer record based on their unique identifier.</description>
    <in-parameters>
        <parameter name="partyId" required="true"/>
    </in-parameters>
    <out-parameters>
        <parameter name="customerInfo" type="Map"/>
    </out-parameters>
    <actions>
        <set field="customerInfo" from="[:]"/>
        
        <!-- 1. Fetch Person Base Data -->
        <entity-find-one entity-name="Person" value-field="person">
            <field-map field-name="partyId" from="partyId"/>
        </entity-find-one>
        <if condition="!person">
            <return error="true" message="Customer not found for ID: ${partyId}"/>
        </if>
        
        <script>
            customerInfo.putAll(person)
            customerInfo.emails = []
            customerInfo.phones = []
            customerInfo.addresses = []
        </script>

        <!-- 2. Fetch Active Contact Mechanisms via view-entity or direct join -->
        <entity-find entity-name="PartyContactMech" list="contactMechs">
            <econdition field-name="partyId" from="partyId"/>
            <econdition field-name="thruDate" operator="is-null"/>
        </entity-find>

        <iterate list="contactMechs" entry="pcm">
            <entity-find-one entity-name="ContactMech" value-field="cm">
                <field-map field-name="contactMechId" from="pcm.contactMechId"/>
            </entity-find-one>

            <if condition="cm.contactMechTypeEnumId == 'EMAIL_ADDRESS'">
                <script>customerInfo.emails.add([email: cm.infoString, purpose: pcm.contactMechPurposeEnumId])</script>
            <else-if condition="cm.contactMechTypeEnumId == 'TELECOM_NUMBER'">
                <entity-find-one entity-name="TelecomNumber" value-field="telecom">
                    <field-map field-name="contactMechId" from="cm.contactMechId"/>
                </entity-find-one>
                <script>customerInfo.phones.add([number: telecom.contactNumber, purpose: pcm.contactMechPurposeEnumId])</script>
            </else-if>
            <else-if condition="cm.contactMechTypeEnumId == 'POSTAL_ADDRESS'">
                <entity-find-one entity-name="PostalAddress" value-field="postal">
                    <field-map field-name="contactMechId" from="cm.contactMechId"/>
                </entity-find-one>
                <script>customerInfo.addresses.add([address1: postal.address1, city: postal.city, zip: postal.postalCode, purpose: pcm.contactMechPurposeEnumId])</script>
            </else-if>
            </if>
        </iterate>
    </actions>
</service>
```

## 3. Update an Existing Customer Record

```xml
<service verb="update" noun="Customer">
    <description>Updates an existing customer record, expiring old contact info if changed.</description>
    <in-parameters>
        <parameter name="partyId" required="true"/>
        <parameter name="firstName"/>
        <parameter name="lastName"/>
        <parameter name="newEmailAddress"/>
    </in-parameters>
    <actions>
        <!-- 1. Update Base Info if provided -->
        <if condition="firstName || lastName">
            <service-call name="update#Person" in-map="[partyId: partyId, firstName: firstName, lastName: lastName]"/>
        </if>

        <!-- 2. Update Email: Expire old email and insert new one -->
        <if condition="newEmailAddress">
            <!-- Find existing primary emails and expire them -->
            <entity-find entity-name="PartyContactMech" list="oldEmails">
                <econdition field-name="partyId" from="partyId"/>
                <econdition field-name="contactMechPurposeEnumId" value="PRIMARY_EMAIL"/>
                <econdition field-name="thruDate" operator="is-null"/>
            </entity-find>
            
            <iterate list="oldEmails" entry="oldEmail">
                <service-call name="update#PartyContactMech" 
                    in-map="[partyId: oldEmail.partyId, contactMechId: oldEmail.contactMechId, contactMechPurposeEnumId: oldEmail.contactMechPurposeEnumId, fromDate: oldEmail.fromDate, thruDate: ec.user.nowTimestamp]"/>
            </iterate>
            
            <!-- Insert new email -->
            <service-call name="create#ContactMech" in-map="[contactMechTypeEnumId: 'EMAIL_ADDRESS', infoString: newEmailAddress]" out-map="emailOut"/>
            <service-call name="create#PartyContactMech" 
                in-map="[partyId: partyId, contactMechId: emailOut.contactMechId, contactMechPurposeEnumId: 'PRIMARY_EMAIL', fromDate: ec.user.nowTimestamp]"/>
        </if>
    </actions>
</service>
```

## 4. Delete a Customer Record (Soft Delete)

```xml
<service verb="delete" noun="Customer">
    <description>Soft deletes a customer by expiring all their active contact mechanisms.</description>
    <in-parameters>
        <parameter name="partyId" required="true"/>
    </in-parameters>
    <actions>
        <!-- Expire all Contact Mechanisms -->
        <entity-find entity-name="PartyContactMech" list="activeMechs">
            <econdition field-name="partyId" from="partyId"/>
            <econdition field-name="thruDate" operator="is-null"/>
        </entity-find>

        <iterate list="activeMechs" entry="pcm">
            <service-call name="update#PartyContactMech" 
                in-map="[partyId: pcm.partyId, contactMechId: pcm.contactMechId, contactMechPurposeEnumId: pcm.contactMechPurposeEnumId, fromDate: pcm.fromDate, thruDate: ec.user.nowTimestamp]"/>
        </iterate>
        
        <!-- Optionally update a statusId on Party if present in schema -->
    </actions>
</service>
```
