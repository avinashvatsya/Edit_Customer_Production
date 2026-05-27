/**
 * EditCustomerCMDMCallout
 * 
 * PATCHes customer details to CMDM via PolicyClaimCustomerSystem Named Credential.
 * Uses raw HTTP (not External Service) for full control over headers + media type.
 * 
 * Media type: application/vnd.api+json (JSON:API spec)
 * Required headers: X-Client-Id, X-Client-Version, X-Request-Id
 */
public with sharing class EditCustomerCMDMCallout {

    private static final String NAMED_CRED  = 'callout:PolicyClaimCustomerSystem';
    private static final String BRAND       = 'AAINZ';
    private static final String BASE_PATH   = '/customer-api/v3/brands/';
    private static final String CLIENT_ID   = 'AAICRM';
    private static final String CLIENT_VER  = '1';
    private static final String MEDIA_TYPE  = 'application/vnd.api+json';
    private static final Integer TIMEOUT_MS = 30000;
    private static final String SOURCE_SYSTEM_CODE = 'CRM';   // max 3 chars
    private static final Integer MAX_LAST_MODIFIED_BY = 20;

    public class EditCustomerRequest {
        @InvocableVariable(required=true) public String accountId;
        @InvocableVariable public Boolean isPersonAccount;
        @InvocableVariable public String accountName;       // For business accounts
        @InvocableVariable public String firstName;
        @InvocableVariable public String middleName;
        @InvocableVariable public String lastName;
        @InvocableVariable public String preferredName;
        @InvocableVariable public String title;             // Salutation: Mr/Mrs/Ms/...
        @InvocableVariable public Date   birthdate;
        @InvocableVariable public String gender;            // MALE / FEMALE / UNKNOWN / INDETERMINATE
        @InvocableVariable public String marketingConsent;
        @InvocableVariable public String mobile;
        @InvocableVariable public String email;
        @InvocableVariable public String streetNumber;
        @InvocableVariable public String streetName;
        @InvocableVariable public String streetType;
        @InvocableVariable public String locality;
        @InvocableVariable public String townCity;
        @InvocableVariable public String state;
        @InvocableVariable public String postcode;
        @InvocableVariable public String country;
        @InvocableVariable public String buildingName;
        @InvocableVariable public String unitType;
        @InvocableVariable public String unitNumber;
        @InvocableVariable public String levelType;
        @InvocableVariable public String levelNumber;
        @InvocableVariable public String aaMembershipNumber;
        @InvocableVariable public String aaMembershipStartDate;
        @InvocableVariable public Boolean nameChanged;
        @InvocableVariable public Boolean titleChanged;
        @InvocableVariable public Boolean preferredNameChanged;
        @InvocableVariable public Boolean dobChanged;
        @InvocableVariable public Boolean genderChanged;
        @InvocableVariable public Boolean marketingConsentChanged;
        @InvocableVariable public Boolean mobileChanged;
        @InvocableVariable public Boolean emailChanged;
        @InvocableVariable public Boolean addressChanged;
        @InvocableVariable public Boolean membershipChanged;
    }

    public class EditCustomerResponse {
        @InvocableVariable public Boolean isSuccess;
        @InvocableVariable public String  errorMessage;
        @InvocableVariable public Integer responseCode;
    }

    @InvocableMethod(label='Submit Customer Edit to CMDM' category='Edit Customer')
    public static List<EditCustomerResponse> submitToCMDM(List<EditCustomerRequest> requests) {
        List<EditCustomerResponse> responses = new List<EditCustomerResponse>();
        for (EditCustomerRequest req : requests) responses.add(processOne(req));
        return responses;
    }

    private static EditCustomerResponse processOne(EditCustomerRequest req) {
        EditCustomerResponse resp = new EditCustomerResponse();
        try {
            Account acc = [SELECT Id, Name, FirstName, LastName, IsPersonAccount, SourceSystemId__c FROM Account
                          WHERE Id = :req.accountId LIMIT 1];

            if (String.isBlank(acc.SourceSystemId__c)) {
                resp.isSuccess = false;
                resp.errorMessage = 'This customer is not linked to CMDM (no Customer ID found).';
                return resp;
            }

            Map<String, Object> payload = buildPayload(req, acc);
            String body = JSON.serialize(payload, true);
            System.debug(LoggingLevel.INFO, 'CMDM PATCH payload: ' + body);

            HttpResponse httpResp = sendPatch(acc.SourceSystemId__c, body);
            resp.responseCode = httpResp.getStatusCode();
            System.debug(LoggingLevel.INFO, 'CMDM response: ' + httpResp.getStatusCode() 
                + ' body=' + httpResp.getBody());

            if (httpResp.getStatusCode() >= 200 && httpResp.getStatusCode() < 300) {
                resp.isSuccess = true;
            } else {
                resp.isSuccess = false;
                resp.errorMessage = parseErrorMessage(httpResp);
            }
        } catch (Exception e) {
            resp.isSuccess = false;
            resp.errorMessage = e.getTypeName() + ': ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'CMDM exception: ' + e.getMessage() 
                + '\n' + e.getStackTraceString());
        }
        return resp;
    }

    private static HttpResponse sendPatch(String cmdmId, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CRED + BASE_PATH + BRAND + '/customers/' + cmdmId);
        req.setMethod('PATCH');
        req.setHeader('Content-Type',    MEDIA_TYPE);
        req.setHeader('Accept',          MEDIA_TYPE);
        req.setHeader('X-Client-Id',     CLIENT_ID);
        req.setHeader('X-Client-Version',CLIENT_VER);
        req.setHeader('X-Request-Id',    'SF-' + UserInfo.getOrganizationId() + '-' + Datetime.now().getTime());
        req.setBody(body);
        req.setTimeout(TIMEOUT_MS);
        return new Http().send(req);
    }

    private static Map<String, Object> buildPayload(EditCustomerRequest req, Account acc) {
        Map<String, Object> partyDetails = new Map<String, Object>();
        partyDetails.put('partyIDRef', acc.SourceSystemId__c);

        Boolean isPerson = req.isPersonAccount == null ? true : req.isPersonAccount;

        if (isPerson) {
            if (req.nameChanged == true || req.dobChanged == true || req.genderChanged == true || req.titleChanged == true) {
                partyDetails.put('individual', buildIndividual(req, acc));
            }
        } else {
            if (req.nameChanged == true) {
                partyDetails.put('organisation', buildOrganisation(req, acc));
            }
        }
        if (req.addressChanged == true) {
            partyDetails.put('postalContact', buildAddress(req));
        }
        if (req.mobileChanged == true) {
            partyDetails.put('phoneContact', buildPhoneContacts(req));
        }
        if (req.emailChanged == true) {
            partyDetails.put('emailContact', buildEmailContacts(req));
        }
        if (req.membershipChanged == true) {
            partyDetails.put('membership', buildMemberships(req));
        }
        partyDetails.put('extensionFields', buildExtensionFields());

        return new Map<String, Object>{
            'data' => new Map<String, Object>{
                'id'    => acc.SourceSystemId__c,
                'type'  => isPerson ? 'Individual' : 'Organisation',
                'attributes' => new Map<String, Object>{ 'partyDetails' => partyDetails }
            }
        };
    }

    private static Map<String, Object> buildOrganisation(EditCustomerRequest req, Account acc) {
        Map<String, Object> org = new Map<String, Object>();
        String name = String.isNotBlank(req.accountName) ? req.accountName : acc.Name;
        if (String.isNotBlank(name)) org.put('registeredName', name);
        return org;
    }

    private static Map<String, Object> buildIndividual(EditCustomerRequest req, Account acc) {
        // CMDM rule: firstName AND lastName both REQUIRED if individual block is in PATCH.
        // We build the block when name, DOB, OR gender changes — so always fall back to
        // the Account values for firstName and lastName if the user didn't provide them.
        Map<String, Object> ind = new Map<String, Object>();
        if (req.nameChanged == true) {
            if (String.isNotBlank(req.firstName))  ind.put('firstName', req.firstName);
            if (String.isNotBlank(req.middleName)) ind.put('middleName', req.middleName);
            if (String.isNotBlank(req.lastName))   ind.put('lastName', req.lastName);
        }
        if (req.dobChanged == true && req.birthdate != null) {
            ind.put('dateOfBirth', String.valueOf(req.birthdate));
        }
        if (req.genderChanged == true && String.isNotBlank(req.gender)) {
            ind.put('gender', req.gender.toUpperCase());
        }
        if (req.titleChanged == true && String.isNotBlank(req.title)) {
            ind.put('title', req.title);
        }
        // Always include firstName + lastName when individual block is sent (CMDM requires both)
        if (!ind.isEmpty()) {
            if (!ind.containsKey('firstName')) {
                ind.put('firstName', String.isNotBlank(req.firstName) ? req.firstName : acc.FirstName);
            }
            if (!ind.containsKey('lastName')) {
                ind.put('lastName', String.isNotBlank(req.lastName) ? req.lastName : acc.LastName);
            }
        }
        return ind;
    }

    private static Map<String, Object> buildAddress(EditCustomerRequest req) {
        Map<String, Object> addr = new Map<String, Object>{ 'addressType' => 'POSTAL' };
        if (String.isNotBlank(req.buildingName)) addr.put('buildingName', req.buildingName);
        if (String.isNotBlank(req.unitType))     addr.put('unitType', req.unitType);
        if (String.isNotBlank(req.unitNumber))   addr.put('unitNumber', req.unitNumber);
        if (String.isNotBlank(req.levelType))    addr.put('levelType', req.levelType);
        if (String.isNotBlank(req.levelNumber))  addr.put('levelNumber', req.levelNumber);
        if (String.isNotBlank(req.streetNumber)) addr.put('streetNumber', req.streetNumber);
        if (String.isNotBlank(req.streetName))   addr.put('streetName', req.streetName);

        // CMDM rule: for NZ addresses, only `locality` is accepted (not `townCity`).
        // Combine: prefer locality, fall back to townCity. Append city if both present.
        String localityToSend = combineLocality(req.locality, req.townCity);
        if (String.isNotBlank(localityToSend)) addr.put('locality', localityToSend);

        if (String.isNotBlank(req.state))        addr.put('state', req.state);
        if (String.isNotBlank(req.postcode))     addr.put('postcode', req.postcode);
        String c = normaliseCountry(req.country);
        if (String.isNotBlank(c))                addr.put('country', c);
        return addr;
    }

    /**
     * Combine locality + townCity into a single value CMDM accepts.
     * Examples:
     *   locality="Owhata", townCity="Rotorua"   → "Owhata, Rotorua"
     *   locality="Owhata", townCity=null        → "Owhata"
     *   locality=null,     townCity="Rotorua"   → "Rotorua"
     *   Same value in both                      → just one
     */
    private static String combineLocality(String locality, String townCity) {
        Boolean hasLoc  = String.isNotBlank(locality);
        Boolean hasCity = String.isNotBlank(townCity);
        if (!hasLoc && !hasCity) return null;
        if (hasLoc && !hasCity) return locality;
        if (!hasLoc && hasCity) return townCity;
        if (locality.trim().equalsIgnoreCase(townCity.trim())) return locality;
        return locality + ', ' + townCity;
    }

    private static List<Object> buildPhoneContacts(EditCustomerRequest req) {
        List<Object> phones = new List<Object>();
        if (String.isBlank(req.mobile)) return phones;
        Map<String, Object> phone = new Map<String, Object>{ 'phoneType' => 'MOBILE_PHONE' };
        String mobileNum = req.mobile.trim();
        if (mobileNum.startsWith('+64')) {
            phone.put('countryCode', '+64');
            phone.put('phoneNumber', mobileNum.substring(3).replaceAll('[^0-9]', ''));
        } else if (mobileNum.startsWith('0')) {
            phone.put('countryCode', '+64');
            phone.put('phoneNumber', mobileNum.substring(1).replaceAll('[^0-9]', ''));
        } else {
            phone.put('phoneNumber', mobileNum.replaceAll('[^0-9]', ''));
        }
        phones.add(phone);
        return phones;
    }

    private static List<Object> buildEmailContacts(EditCustomerRequest req) {
        List<Object> emails = new List<Object>();
        if (String.isBlank(req.email)) return emails;
        emails.add(new Map<String, Object>{ 'emailAddress' => req.email.trim() });
        return emails;
    }

    private static List<Object> buildMemberships(EditCustomerRequest req) {
        List<Object> memberships = new List<Object>();
        Boolean hasNumber = String.isNotBlank(req.aaMembershipNumber);
        Boolean hasDate   = String.isNotBlank(req.aaMembershipStartDate);

        // Both blank → empty array signals deletion
        if (!hasNumber && !hasDate) return memberships;

        // Only one provided → reject before sending (CMDM requires both)
        if (hasNumber != hasDate) {
            throw new IllegalArgumentException(
                'AA Membership requires both number AND start date (MM/YYYY). ' +
                'Please complete both fields or leave both blank.');
        }

        String normalisedDate = normaliseMembershipDate(req.aaMembershipStartDate);
        if (!Pattern.matches('^(0[1-9]|1[0-2])-[0-9]{4}$', normalisedDate)) {
            throw new IllegalArgumentException(
                'AA Membership start date must be in MM/YYYY format (e.g. 03/2020).');
        }

        String idRef = req.aaMembershipNumber.replaceAll('[^0-9]', '');
        if (String.isBlank(idRef)) {
            throw new IllegalArgumentException('AA Membership number must contain digits.');
        }

        memberships.add(new Map<String, Object>{
            'membershipType'  => 'AA Membership',
            'membershipIdRef' => idRef,
            'startDate'       => normalisedDate
        });
        return memberships;
    }

    public class IllegalArgumentException extends Exception {}

    private static List<Object> buildExtensionFields() {
        String userId = getCurrentUserUNumber();
        if (userId.length() > MAX_LAST_MODIFIED_BY) {
            userId = userId.substring(0, MAX_LAST_MODIFIED_BY);
        }
        return new List<Object>{
            new Map<String, Object>{
                'extensionFieldsType'     => 'Customer',
                'extensionFieldsCategory' => 'Audit',
                'extensionField' => new List<Object>{
                    new Map<String, Object>{ 'key' => 'sourceSystemModified', 'value' => SOURCE_SYSTEM_CODE },
                    new Map<String, Object>{ 'key' => 'lastModifiedBy', 'value' => userId }
                }
            }
        };
    }

    private static String parseErrorMessage(HttpResponse resp) {
        String body = resp.getBody();
        if (String.isBlank(body)) return 'CMDM returned ' + resp.getStatusCode() + ' with empty body.';
        try {
            Map<String, Object> obj = (Map<String, Object>) JSON.deserializeUntyped(body);
            List<Object> errors = (List<Object>) obj.get('errors');
            if (errors != null && !errors.isEmpty()) {
                List<String> messages = new List<String>();
                for (Object err : errors) {
                    Map<String, Object> e = (Map<String, Object>) err;
                    messages.add(String.format('[{0}] {1}: {2}', new List<String>{
                        String.valueOf(e.get('code')), String.valueOf(e.get('title')), String.valueOf(e.get('details'))
                    }));
                }
                return String.join(messages, ' | ');
            }
        } catch (Exception ignored) {}
        return 'CMDM error ' + resp.getStatusCode() + ': ' + body.left(500);
    }

    private static String normaliseCountry(String country) {
        if (String.isBlank(country)) return null;
        if (country.length() == 2) return country.toUpperCase();
        Map<String, String> codes = new Map<String, String>{
            'New Zealand' => 'NZ', 'Australia' => 'AU',
            'United States' => 'US', 'United Kingdom' => 'GB'
        };
        String code = codes.get(country);
        return code != null ? code : country.substring(0, Math.min(2, country.length())).toUpperCase();
    }

    private static String normaliseMembershipDate(String mmYyyy) {
        if (String.isBlank(mmYyyy)) return null;
        String cleaned = mmYyyy.trim().replace('/', '-').replace('.', '-');
        if (Pattern.matches('^[0-9]{1,2}-[0-9]{4}$', cleaned)) {
            List<String> parts = cleaned.split('-');
            String mm = parts[0].length() == 1 ? '0' + parts[0] : parts[0];
            return mm + '-' + parts[1];
        }
        return cleaned;
    }
    /**
     * Returns the current user's UNumber__c (preferred) or falls back to User Id.
     * Cached per transaction to avoid repeat SOQL.
     */
    @TestVisible private static String cachedUNumber;
    private static String getCurrentUserUNumber() {
        if (cachedUNumber != null) return cachedUNumber;
        try {
            User u = [SELECT UNumber__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            cachedUNumber = String.isNotBlank(u.UNumber__c)
                ? u.UNumber__c
                : String.valueOf(UserInfo.getUserId()).substring(0, 18);
        } catch (Exception e) {
            cachedUNumber = String.valueOf(UserInfo.getUserId()).substring(0, 18);
        }
        return cachedUNumber;
    }
}
