@IsTest
private class EditCustomerCMDMCalloutTest {

    // External Service operations cannot be directly mocked in tests,
    // so these tests cover the path leading up to the call and the
    // payload-building helpers (made testable via @TestVisible if needed).

    private static Id personAccountRT() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
    }

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            RecordTypeId = personAccountRT(),
            FirstName = 'Test',
            LastName = 'CMDMCustomer',
            PersonEmail = 'test@aai.co.nz',
            PersonMobilePhone = '0211234567',
            SourceSystemId__c = 'CMDM-TEST-001'
        );
        insert acc;

        // Account without CMDM ID
        Account orphanAcc = new Account(
            RecordTypeId = personAccountRT(),
            FirstName = 'No',
            LastName = 'CMDMId'
        );
        insert orphanAcc;
    }

    private static EditCustomerCMDMCallout.EditCustomerRequest baseRequest(Id accountId) {
        EditCustomerCMDMCallout.EditCustomerRequest req = new EditCustomerCMDMCallout.EditCustomerRequest();
        req.accountId = accountId;
        req.nameChanged = false;
        req.preferredNameChanged = false;
        req.dobChanged = false;
        req.marketingConsentChanged = false;
        req.mobileChanged = false;
        req.emailChanged = false;
        req.addressChanged = false;
        req.membershipChanged = false;
        return req;
    }

    @IsTest
    static void submit_noSourceSystemId_returnsError() {
        Account acc = [SELECT Id FROM Account WHERE LastName = 'CMDMId' LIMIT 1];
        EditCustomerCMDMCallout.EditCustomerRequest req = baseRequest(acc.Id);
        req.firstName = 'Updated';
        req.nameChanged = true;

        Test.startTest();
        List<EditCustomerCMDMCallout.EditCustomerResponse> resp =
            EditCustomerCMDMCallout.submitToCMDM(
                new List<EditCustomerCMDMCallout.EditCustomerRequest>{ req });
        Test.stopTest();

        Assert.isFalse(resp[0].isSuccess);
        Assert.isTrue(resp[0].errorMessage.contains('not linked to CMDM'));
    }

    @IsTest
    static void submit_invalidAccountId_returnsError() {
        EditCustomerCMDMCallout.EditCustomerRequest req = baseRequest(null);

        Test.startTest();
        List<EditCustomerCMDMCallout.EditCustomerResponse> resp =
            EditCustomerCMDMCallout.submitToCMDM(
                new List<EditCustomerCMDMCallout.EditCustomerRequest>{ req });
        Test.stopTest();

        Assert.isFalse(resp[0].isSuccess);
        Assert.isNotNull(resp[0].errorMessage);
    }

    @IsTest
    static void emptyRequestList_returnsEmpty() {
        Test.startTest();
        List<EditCustomerCMDMCallout.EditCustomerResponse> resp =
            EditCustomerCMDMCallout.submitToCMDM(new List<EditCustomerCMDMCallout.EditCustomerRequest>());
        Test.stopTest();

        Assert.areEqual(0, resp.size());
    }
}
