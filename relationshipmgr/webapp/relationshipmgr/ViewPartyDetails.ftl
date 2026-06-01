<div class="container" style="margin-top: 20px;">
    <!-- Header Summary -->
    <div class="panel panel-primary">
        <div class="panel-heading">
            <h3 class="panel-title">
                <#if person??>
                    Person Details: ${person.firstName!} ${person.lastName!}
                <#elseif organization??>
                    Organization Details: ${organization.organizationName!}
                <#else>
                    Party Details [${party.partyId}]
                </#if>
            </h3>
        </div>
        <div class="panel-body">
            <div class="row">
                <div class="col-md-6">
                    <table class="table table-bordered">
                        <tr>
                            <th>Party ID</th>
                            <td>${party.partyId}</td>
                        </tr>
                        <tr>
                            <th>Party Type</th>
                            <td>${party.partyTypeId}</td>
                        </tr>
                        <#if person??>
                            <tr>
                                <th>First Name</th>
                                <td>${person.firstName!}</td>
                            </tr>
                            <tr>
                                <th>Last Name</th>
                                <td>${person.lastName!}</td>
                            </tr>
                            <tr>
                                <th>Birth Date</th>
                                <td>${person.birthDate!}</td>
                            </tr>
                        <#elseif organization??>
                            <tr>
                                <th>Organization Name</th>
                                <td>${organization.organizationName!}</td>
                            </tr>
                        </#if>
                    </table>
                </div>
                
                <div class="col-md-6">
                    <h4>Assigned Roles</h4>
                    <table class="table table-striped table-bordered">
                        <thead>
                            <tr>
                                <th>Role Type ID</th>
                            </tr>
                        </thead>
                        <tbody>
                            <#if partyRoles?? && (partyRoles?size > 0)>
                                <#list partyRoles as partyRole>
                                    <tr>
                                        <td>${partyRole.roleTypeId}</td>
                                    </tr>
                                </#list>
                            <#else>
                                <tr>
                                    <td>No roles assigned to this party.</td>
                                </tr>
                            </#if>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <!-- Contact Mechanisms -->
    <div class="panel panel-info">
        <div class="panel-heading">
            <h3 class="panel-title">Contact Mechanisms</h3>
        </div>
        <div class="panel-body">
            <table class="table table-bordered table-striped">
                <thead>
                    <tr>
                        <th>Purpose</th>
                        <th>Type</th>
                        <th>Details</th>
                        <th>From Date</th>
                    </tr>
                </thead>
                <tbody>
                    <#if contactMechList?? && (contactMechList?size > 0)>
                        <#list contactMechList as contact>
                            <tr>
                                <td><strong>${contact.contactMechPurposeId}</strong></td>
                                <td><span class="label label-info">${contact.contactMechTypeEnumId}</span></td>
                                <td>
                                    <#if contact.contactMechTypeEnumId == "EMAIL_ADDRESS">
                                        <a href="mailto:${contact.infoString!}">${contact.infoString!}</a>
                                    <#elseif contact.contactMechTypeEnumId == "TELECOM_NUMBER">
                                        <#if contact.telecom??>
                                            +${contact.telecom.countryCode!} (${contact.telecom.areaCode!}) ${contact.telecom.contactNumber!}
                                        <#else>
                                            No telecom details found.
                                        </#if>
                                    <#elseif contact.contactMechTypeEnumId == "POSTAL_ADDRESS">
                                        <#if contact.postal??>
                                            ${contact.postal.toName!}<br/>
                                            <#if contact.postal.attnName?has_content>Attn: ${contact.postal.attnName!}<br/></#if>
                                            ${contact.postal.address1!}<br/>
                                            <#if contact.postal.address2?has_content>${contact.postal.address2!}<br/></#if>
                                            ${contact.postal.city!}, ${contact.postal.postalCode!}
                                        <#else>
                                            No postal address details found.
                                        </#if>
                                    <#else>
                                        ${contact.infoString!}
                                    </#if>
                                </td>
                                <td>${contact.fromDate!}</td>
                            </tr>
                        </#list>
                    <#else>
                        <tr>
                            <td colspan="4">No contact mechanisms associated with this party.</td>
                        </tr>
                    </#if>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Quick Add Contact Panels -->
    <div class="row">
        <!-- Add Phone -->
        <div class="col-md-4">
            <div class="panel panel-default">
                <div class="panel-heading">Add Telecom Number</div>
                <div class="panel-body">
                    <form action="<@ofbizUrl>createTelecom</@ofbizUrl>" method="post">
                        <input type="hidden" name="partyId" value="${party.partyId}"/>
                        <div class="form-group">
                            <label>Purpose</label>
                            <select name="contactMechPurposeId" class="form-control">
                                <option value="WORK">Work</option>
                                <option value="HOME">Home</option>
                                <option value="OFFICE">Office</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Country Code</label>
                            <input type="text" name="countryCode" value="91" class="form-control"/>
                        </div>
                        <div class="form-group">
                            <label>Area Code</label>
                            <input type="text" name="areaCode" class="form-control"/>
                        </div>
                        <div class="form-group">
                            <label>Contact Number</label>
                            <input type="text" name="contactNumber" required class="form-control"/>
                        </div>
                        <button type="submit" class="btn btn-success btn-block">Add Phone</button>
                    </form>
                </div>
            </div>
        </div>

        <!-- Add Email -->
        <div class="col-md-4">
            <div class="panel panel-default">
                <div class="panel-heading">Add Email Address</div>
                <div class="panel-body">
                    <form action="<@ofbizUrl>createEmail</@ofbizUrl>" method="post">
                        <input type="hidden" name="partyId" value="${party.partyId}"/>
                        <div class="form-group">
                            <label>Purpose</label>
                            <select name="contactMechPurposeId" class="form-control">
                                <option value="WORK">Work</option>
                                <option value="HOME">Home</option>
                                <option value="OFFICE">Office</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Email Address</label>
                            <input type="email" name="infoString" required class="form-control"/>
                        </div>
                        <button type="submit" class="btn btn-primary btn-block">Add Email</button>
                    </form>
                </div>
            </div>
        </div>

        <!-- Add Address -->
        <div class="col-md-4">
            <div class="panel panel-default">
                <div class="panel-heading">Add Postal Address</div>
                <div class="panel-body">
                    <form action="<@ofbizUrl>createPostal</@ofbizUrl>" method="post">
                        <input type="hidden" name="partyId" value="${party.partyId}"/>
                        <div class="form-group">
                            <label>Purpose</label>
                            <select name="contactMechPurposeId" class="form-control">
                                <option value="WORK">Work</option>
                                <option value="HOME">Home</option>
                                <option value="OFFICE">Office</option>
                                <option value="BILLING_LOCATION">Billing</option>
                                <option value="SHIPPING_LOCATION">Shipping</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>To Name</label>
                            <input type="text" name="toName" required class="form-control"/>
                        </div>
                        <div class="form-group">
                            <label>Attn Name</label>
                            <input type="text" name="attnName" class="form-control"/>
                        </div>
                        <div class="form-group">
                            <label>Address Line 1</label>
                            <input type="text" name="address1" required class="form-control"/>
                        </div>
                        <div class="form-group">
                            <label>Address Line 2</label>
                            <input type="text" name="address2" class="form-control"/>
                        </div>
                        <div class="form-group">
                            <label>City</label>
                            <input type="text" name="city" required class="form-control"/>
                        </div>
                        <div class="form-group">
                            <label>Postal Code</label>
                            <input type="text" name="postalCode" required class="form-control"/>
                        </div>
                        <button type="submit" class="btn btn-warning btn-block">Add Address</button>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>
