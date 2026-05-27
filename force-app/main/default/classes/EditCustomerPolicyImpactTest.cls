@IsTest
private class EditCustomerPolicyImpactTest {

    private static Id personAccountRT() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
    }

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            RecordTypeId = personAccountRT(),
            FirstName = 'Policy',
            LastName = 'Tester',
            PersonEmail = 'tester@aai.co.nz'
        );
        insert acc;

        Account noPolicyAcc = new Account(
            RecordTypeId = personAccountRT(),
            FirstName = 'Empty',
            LastName = 'Customer'
        );
        insert noPolicyAcc;

        List<InsurancePolicy> policies = new List<InsurancePolicy>{
            new InsurancePolicy(Name = 'DC-001', PolicyName = 'DC-001', Status = 'Active', SourceSystem = 'DuckCreek', NameInsuredId = acc.Id),
            new InsurancePolicy(Name = 'DC-002', PolicyName = 'DC-002', Status = 'Active', SourceSystem = 'DuckCreek', NameInsuredId = acc.Id),
            new InsurancePolicy(Name = 'PR-001', PolicyName = 'PR-001', Status = 'Active', SourceSystem = 'Protect', NameInsuredId = acc.Id),
            new InsurancePolicy(Name = 'INACTIVE-DC-001', PolicyName = 'INACTIVE-DC-001', Status = 'Cancelled', SourceSystem = 'DuckCreek', NameInsuredId = acc.Id)
        };
        insert policies;

        List<InsurancePolicyParticipant> participants = new List<InsurancePolicyParticipant>();
        for (InsurancePolicy p : policies) {
            participants.add(new InsurancePolicyParticipant(
                InsurancePolicyId = p.Id,
                PrimaryParticipantAccountId = acc.Id,
                BeginDate = Date.today()
            ));
        }
        insert participants;
    }

    @IsTest
    static void getPolicyImpact_withPolicies_returnsGrouped() {
        Account acc = [SELECT Id FROM Account WHERE FirstName = 'Policy' LIMIT 1];

        EditCustomerPolicyImpact.PolicyImpactRequest req = new EditCustomerPolicyImpact.PolicyImpactRequest();
        req.accountId = acc.Id;

        Test.startTest();
        List<EditCustomerPolicyImpact.PolicyImpactResponse> resp =
            EditCustomerPolicyImpact.getPolicyImpact(
                new List<EditCustomerPolicyImpact.PolicyImpactRequest>{ req });
        Test.stopTest();

        Assert.areEqual(2, resp[0].dcCount, 'Should return 2 active DC policies');
        Assert.areEqual(1, resp[0].protectCount, 'Should return 1 Protect policy');
        Assert.isTrue(resp[0].hasProtectPolicies);
        Assert.areEqual('tester@aai.co.nz', resp[0].endConsentEmail);
    }

    @IsTest
    static void getPolicyImpact_noPolicies_returnsEmpty() {
        Account acc = [SELECT Id FROM Account WHERE FirstName = 'Empty' LIMIT 1];

        EditCustomerPolicyImpact.PolicyImpactRequest req = new EditCustomerPolicyImpact.PolicyImpactRequest();
        req.accountId = acc.Id;

        Test.startTest();
        List<EditCustomerPolicyImpact.PolicyImpactResponse> resp =
            EditCustomerPolicyImpact.getPolicyImpact(
                new List<EditCustomerPolicyImpact.PolicyImpactRequest>{ req });
        Test.stopTest();

        Assert.areEqual(0, resp[0].dcCount);
        Assert.areEqual(0, resp[0].protectCount);
        Assert.isFalse(resp[0].hasProtectPolicies);
    }

    @IsTest
    static void getPolicyImpact_nullId_returnsEmpty() {
        EditCustomerPolicyImpact.PolicyImpactRequest req = new EditCustomerPolicyImpact.PolicyImpactRequest();
        req.accountId = null;

        Test.startTest();
        List<EditCustomerPolicyImpact.PolicyImpactResponse> resp =
            EditCustomerPolicyImpact.getPolicyImpact(
                new List<EditCustomerPolicyImpact.PolicyImpactRequest>{ req });
        Test.stopTest();

        Assert.areEqual(0, resp[0].dcCount);
        Assert.areEqual(0, resp[0].protectCount);
    }

    @IsTest
    static void getPolicyImpactForLwc_returnsSameData() {
        Account acc = [SELECT Id FROM Account WHERE FirstName = 'Policy' LIMIT 1];

        Test.startTest();
        EditCustomerPolicyImpact.PolicyImpactResponse resp =
            EditCustomerPolicyImpact.getPolicyImpactForLwc(acc.Id);
        Test.stopTest();

        Assert.areEqual(2, resp.dcCount);
        Assert.areEqual(1, resp.protectCount);
    }
}
