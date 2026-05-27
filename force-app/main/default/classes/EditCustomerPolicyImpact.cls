/**
 * EditCustomerPolicyImpact
 * 
 * Returns active policies where the customer is a participant,
 * grouped by source system (Duck Creek = auto-update, Protect = manual).
 * 
 * Used by Edit Customer flow to show impact summary on Screen 3.
 */
public with sharing class EditCustomerPolicyImpact {

    private static final String SOURCE_DC = 'DuckCreek';
    private static final String SOURCE_PROTECT = 'Protect';
    private static final String STATUS_ACTIVE = 'Active';

    // ============================================================
    // Invocable Action (Flow entry point)
    // ============================================================

    @InvocableMethod(label='Get Customer Policy Impact'
                     description='Returns active DC + Protect policies for the customer'
                     category='Edit Customer')
    public static List<PolicyImpactResponse> getPolicyImpact(List<PolicyImpactRequest> requests) {
        List<PolicyImpactResponse> responses = new List<PolicyImpactResponse>();
        for (PolicyImpactRequest req : requests) {
            responses.add(buildResponse(req.accountId));
        }
        return responses;
    }

    // ============================================================
    // AuraEnabled (LWC entry point)
    // ============================================================

    @AuraEnabled(cacheable=true)
    public static PolicyImpactResponse getPolicyImpactForLwc(Id accountId) {
        return buildResponse(accountId);
    }

    // ============================================================
    // Core
    // ============================================================

    private static PolicyImpactResponse buildResponse(Id accountId) {
        PolicyImpactResponse resp = new PolicyImpactResponse();
        resp.dcPolicies = new List<InsurancePolicy>();
        resp.protectPolicies = new List<InsurancePolicy>();
        resp.endConsentEmail = null;

        if (accountId == null) return resp;

        // Customer email for END consent display
        List<Account> accs = [SELECT Id, PersonEmail FROM Account WHERE Id = :accountId LIMIT 1];
        if (!accs.isEmpty()) {
            resp.endConsentEmail = accs[0].PersonEmail;
        }

        // Get participant junction rows
        Set<Id> policyIds = new Set<Id>();
        for (InsurancePolicyParticipant ipp : [
            SELECT InsurancePolicyId
            FROM InsurancePolicyParticipant
            WHERE PrimaryParticipantAccountId = :accountId
        ]) {
            if (ipp.InsurancePolicyId != null) policyIds.add(ipp.InsurancePolicyId);
        }

        if (policyIds.isEmpty()) {
            resp.dcCount = 0;
            resp.protectCount = 0;
            resp.hasProtectPolicies = false;
            return resp;
        }

        // Get active policies, group by source system
        for (InsurancePolicy p : [
            SELECT Id, Name, SourceSystem, Status
            FROM InsurancePolicy
            WHERE Id IN :policyIds
              AND Status = :STATUS_ACTIVE
            ORDER BY Name ASC
        ]) {
            if (SOURCE_DC.equals(p.SourceSystem)) {
                resp.dcPolicies.add(p);
            } else if (SOURCE_PROTECT.equals(p.SourceSystem)) {
                resp.protectPolicies.add(p);
            }
        }

        resp.dcCount = resp.dcPolicies.size();
        resp.protectCount = resp.protectPolicies.size();
        resp.hasProtectPolicies = resp.protectCount > 0;
        return resp;
    }

    // ============================================================
    // Wire Types
    // ============================================================

    public class PolicyImpactRequest {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    public class PolicyImpactResponse {
        @InvocableVariable @AuraEnabled public List<InsurancePolicy> dcPolicies;
        @InvocableVariable @AuraEnabled public List<InsurancePolicy> protectPolicies;
        @InvocableVariable @AuraEnabled public Boolean hasProtectPolicies;
        @InvocableVariable @AuraEnabled public Integer dcCount;
        @InvocableVariable @AuraEnabled public Integer protectCount;
        @InvocableVariable @AuraEnabled public String endConsentEmail;
    }
}
