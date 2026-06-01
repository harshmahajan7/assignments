import org.apache.ofbiz.base.util.UtilDateTime
import org.apache.ofbiz.entity.GenericValue
import org.apache.ofbiz.service.ServiceUtil

def createPersonWithParty() {
    Map result = ServiceUtil.returnSuccess()
    
    String partyId = context.partyId
    if (!partyId) {
        partyId = delegator.getNextSeqId("RmgrParty")
    }
    
    // 1. Create RmgrParty
    GenericValue rmgrParty = delegator.makeValue("RmgrParty", [
        partyId: partyId,
        partyTypeId: "PERSON"
    ])
    delegator.create(rmgrParty)
    
    // 2. Create RmgrPerson
    GenericValue rmgrPerson = delegator.makeValue("RmgrPerson", [
        partyId: partyId,
        firstName: context.firstName,
        lastName: context.lastName,
        birthDate: context.birthDate
    ])
    delegator.create(rmgrPerson)
    
    // 3. Create RmgrPartyRole if roleTypeId is provided
    if (context.roleTypeId) {
        GenericValue rmgrPartyRole = delegator.makeValue("RmgrPartyRole", [
            partyId: partyId,
            roleTypeId: context.roleTypeId
        ])
        delegator.create(rmgrPartyRole)
    }
    
    result.partyId = partyId
    return result
}

def createOrganizationWithParty() {
    Map result = ServiceUtil.returnSuccess()
    
    String partyId = context.partyId
    if (!partyId) {
        partyId = delegator.getNextSeqId("RmgrParty")
    }
    
    // 1. Create RmgrParty
    GenericValue rmgrParty = delegator.makeValue("RmgrParty", [
        partyId: partyId,
        partyTypeId: "ORGANIZATION"
    ])
    delegator.create(rmgrParty)
    
    // 2. Create RmgrOrganization
    GenericValue rmgrOrganization = delegator.makeValue("RmgrOrganization", [
        partyId: partyId,
        organizationName: context.organizationName
    ])
    delegator.create(rmgrOrganization)
    
    // 3. Create RmgrPartyRole if roleTypeId is provided
    if (context.roleTypeId) {
        GenericValue rmgrPartyRole = delegator.makeValue("RmgrPartyRole", [
            partyId: partyId,
            roleTypeId: context.roleTypeId
        ])
        delegator.create(rmgrPartyRole)
    }
    
    result.partyId = partyId
    return result
}

def createTelecomNumberWithContact() {
    Map result = ServiceUtil.returnSuccess()
    
    String contactMechId = context.contactMechId
    if (!contactMechId) {
        contactMechId = delegator.getNextSeqId("RmgrContactMech")
    }
    
    // 1. Create RmgrContactMech
    GenericValue contactMech = delegator.makeValue("RmgrContactMech", [
        contactMechId: contactMechId,
        contactMechTypeEnumId: "TELECOM_NUMBER"
    ])
    delegator.create(contactMech)
    
    // 2. Create RmgrTelecomNumber
    GenericValue telecom = delegator.makeValue("RmgrTelecomNumber", [
        contactMechId: contactMechId,
        countryCode: context.countryCode,
        areaCode: context.areaCode,
        contactNumber: context.contactNumber
    ])
    delegator.create(telecom)
    
    // 3. Associate via RmgrPartyContactMech
    GenericValue partyContactMech = delegator.makeValue("RmgrPartyContactMech", [
        partyId: context.partyId,
        contactMechId: contactMechId,
        contactMechPurposeId: context.contactMechPurposeId,
        fromDate: UtilDateTime.nowTimestamp()
    ])
    delegator.create(partyContactMech)
    
    result.contactMechId = contactMechId
    return result
}

def createPostalAddressWithContact() {
    Map result = ServiceUtil.returnSuccess()
    
    String contactMechId = context.contactMechId
    if (!contactMechId) {
        contactMechId = delegator.getNextSeqId("RmgrContactMech")
    }
    
    // 1. Create RmgrContactMech
    GenericValue contactMech = delegator.makeValue("RmgrContactMech", [
        contactMechId: contactMechId,
        contactMechTypeEnumId: "POSTAL_ADDRESS"
    ])
    delegator.create(contactMech)
    
    // 2. Create RmgrPostalAddress
    GenericValue address = delegator.makeValue("RmgrPostalAddress", [
        contactMechId: contactMechId,
        toName: context.toName,
        attnName: context.attnName,
        address1: context.address1,
        address2: context.address2,
        city: context.city,
        postalCode: context.postalCode
    ])
    delegator.create(address)
    
    // 3. Associate via RmgrPartyContactMech
    GenericValue partyContactMech = delegator.makeValue("RmgrPartyContactMech", [
        partyId: context.partyId,
        contactMechId: contactMechId,
        contactMechPurposeId: context.contactMechPurposeId,
        fromDate: UtilDateTime.nowTimestamp()
    ])
    delegator.create(partyContactMech)
    
    result.contactMechId = contactMechId
    return result
}

def createEmailWithContact() {
    Map result = ServiceUtil.returnSuccess()
    
    String contactMechId = context.contactMechId
    if (!contactMechId) {
        contactMechId = delegator.getNextSeqId("RmgrContactMech")
    }
    
    // 1. Create RmgrContactMech
    GenericValue contactMech = delegator.makeValue("RmgrContactMech", [
        contactMechId: contactMechId,
        contactMechTypeEnumId: "EMAIL_ADDRESS",
        infoString: context.infoString
    ])
    delegator.create(contactMech)
    
    // 2. Associate via RmgrPartyContactMech
    GenericValue partyContactMech = delegator.makeValue("RmgrPartyContactMech", [
        partyId: context.partyId,
        contactMechId: contactMechId,
        contactMechPurposeId: context.contactMechPurposeId,
        fromDate: UtilDateTime.nowTimestamp()
    ])
    delegator.create(partyContactMech)
    
    result.contactMechId = contactMechId
    return result
}
