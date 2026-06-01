import org.apache.ofbiz.entity.util.EntityQuery

String partyId = parameters.partyId
if (partyId) {
    context.party = from("RmgrParty").where("partyId", partyId).queryOne()
    if (context.party) {
        if ("PERSON".equals(context.party.partyTypeId)) {
            context.person = from("RmgrPerson").where("partyId", partyId).queryOne()
        } else if ("ORGANIZATION".equals(context.party.partyTypeId)) {
            context.organization = from("RmgrOrganization").where("partyId", partyId).queryOne()
        }
        
        // Roles
        context.partyRoles = from("RmgrPartyRole").where("partyId", partyId).queryList()
        
        // Contact Mechs
        def partyContactMechs = from("RmgrPartyContactMech").where("partyId", partyId).queryList()
        def contactMechList = []
        for (pcm in partyContactMechs) {
            def contactMech = from("RmgrContactMech").where("contactMechId", pcm.contactMechId).queryOne()
            if (contactMech) {
                def details = [:]
                details.contactMechId = pcm.contactMechId
                details.contactMechTypeEnumId = contactMech.contactMechTypeEnumId
                details.infoString = contactMech.infoString
                details.contactMechPurposeId = pcm.contactMechPurposeId
                details.fromDate = pcm.fromDate
                
                if ("TELECOM_NUMBER".equals(contactMech.contactMechTypeEnumId)) {
                    details.telecom = from("RmgrTelecomNumber").where("contactMechId", pcm.contactMechId).queryOne()
                } else if ("POSTAL_ADDRESS".equals(contactMech.contactMechTypeEnumId)) {
                    details.postal = from("RmgrPostalAddress").where("contactMechId", pcm.contactMechId).queryOne()
                }
                contactMechList.add(details)
            }
        }
        context.contactMechList = contactMechList
    }
}
