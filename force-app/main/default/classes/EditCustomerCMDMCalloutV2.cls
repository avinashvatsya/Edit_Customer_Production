/**
 * Invocable Apex callout for CMDM Customer API v2.
 *
 * Endpoint: PATCH /customer-api/v2/brands/{brand}/customers/{customerId}
 * Sample payload structure: data.attributes.{customerType, individual|organisation, addresses, contactMethods, audit}
 *
 * Membership: best-guess structure based on V2 spec sample patterns — see buildMemberships().
 */
public with sharing class EditCustomerCMDMCalloutV2 {

    private static final String NAMED_CREDENTIAL = 'callout:PolicySummaryV4';
    private static final String BRAND            = 'AAINZ';
    private static final String BASE_PATH        = '/customer-api/v2/brands/';
    private static final String CLIENT_ID        = 'AAICRM';
    private static final String CLIENT_VERSION   = '1';
    private static final String CONTENT_TYPE     = 'application/vnd.api+json';
    private static final Integer TIMEOUT_MS      = 120000;
    // TODO confirm exact channelCode / consentAbbr values with CMDM team
    private static final String CONSENT_CHANNEL_TYPE = 'email';
    private static final String CONSENT_CHANNEL_CODE = 'EMAIL';
    private static final String CONSENT_CONSENT_ABBR = 'MKTG';

    public class EditCustomerRequest {
        @InvocableVariable public Id     accountId;
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

        // Address fields (V2 collapses these into addressLine1-5)
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

        // Change flags
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
        @InvocableVariable public Integer statusCode;
    }

    @InvocableMethod(label='Submit Customer Edit to CMDM V2' callout=true)
    public static List<EditCustomerResponse> submit(List<EditCustomerRequest> requests) {
        List<EditCustomerResponse> results = new List<EditCustomerResponse>();
        for (EditCustomerRequest r : requests) {
            results.add(processOne(r));
        }
        return results;
    }

    private static EditCustomerResponse processOne(EditCustomerRequest req) {
        EditCustomerResponse resp = new EditCustomerResponse();
        resp.isSuccess = false;

        try {
            Account acc = [
                SELECT Id, Name, FirstName, LastName, IsPersonAccount, SourceSystemId__c
                FROM Account WHERE Id = :req.accountId LIMIT 1
            ];

            if (String.isBlank(acc.SourceSystemId__c)) {
                throw new IllegalArgumentException('Account is missing SourceSystemId__c (CMDM customer ID).');
            }

            Map<String, Object> payload = buildPayload(req, acc);
            String body = JSON.serialize(payload, true);
            System.debug('CMDM V2 PATCH body: ' + body);

            String endpoint = NAMED_CREDENTIAL + BASE_PATH + BRAND + '/customers/' + acc.SourceSystemId__c;

            HttpRequest http = new HttpRequest();
            http.setEndpoint(endpoint);
            http.setMethod('PATCH');
            http.setTimeout(TIMEOUT_MS);
            http.setHeader('Content-Type', CONTENT_TYPE);
            http.setHeader('Accept', CONTENT_TYPE);
            http.setHeader('X-Client-Id', CLIENT_ID);
            http.setHeader('X-Client-Version', CLIENT_VERSION);
            http.setHeader('X-Request-Id', 'SF-' + String.valueOf(Datetime.now().getTime()));
            http.setBody(body);

            HttpResponse hr = new Http().send(http);
            resp.statusCode = hr.getStatusCode();

            if (hr.getStatusCode() >= 200 && hr.getStatusCode() < 300) {
                resp.isSuccess = true;
            } else {
                resp.errorMessage = parseError(hr.getBody(), hr.getStatusCode());
            }

            // Second call: PATCH consents endpoint when marketing consent changed.
            // Only fires if the main customer PATCH succeeded.
            if (resp.isSuccess && req.marketingConsentChanged == true && String.isNotBlank(req.marketingConsent)) {
                String consentBody = JSON.serialize(buildConsentPayload(acc.SourceSystemId__c, req.marketingConsent), true);
                System.debug('CMDM V2 consent PATCH body: ' + consentBody);
                HttpResponse consentHr = sendConsentPatch(acc.SourceSystemId__c, consentBody);
                System.debug('CMDM V2 consent response: ' + consentHr.getStatusCode()
                    + ' body=' + consentHr.getBody());
                if (consentHr.getStatusCode() < 200 || consentHr.getStatusCode() >= 300) {
                    resp.isSuccess = false;
                    resp.statusCode = consentHr.getStatusCode();
                    resp.errorMessage = 'Customer details updated but marketing consent update failed: '
                        + parseError(consentHr.getBody(), consentHr.getStatusCode());
                }
            }
        } catch (Exception e) {
            resp.errorMessage = e.getMessage();
        }
        return resp;
    }

    private static HttpResponse sendConsentPatch(String cmdmId, String body) {
        String endpoint = NAMED_CREDENTIAL + BASE_PATH + BRAND + '/customers/' + cmdmId + '/consents';
        HttpRequest http = new HttpRequest();
        http.setEndpoint(endpoint);
        http.setMethod('PATCH');
        http.setTimeout(TIMEOUT_MS);
        http.setHeader('Content-Type', CONTENT_TYPE);
        http.setHeader('Accept', CONTENT_TYPE);
        http.setHeader('X-Client-Id', CLIENT_ID);
        http.setHeader('X-Client-Version', CLIENT_VERSION);
        http.setHeader('X-Request-Id', 'SF-' + String.valueOf(Datetime.now().getTime()));
        http.setBody(body);
        return new Http().send(http);
    }

    private static Map<String, Object> buildConsentPayload(String cmdmId, String marketingConsent) {
        return new Map<String, Object>{
            'data' => new Map<String, Object>{
                'id'         => cmdmId,
                'attributes' => new Map<String, Object>{
                    'brand'    => BRAND,
                    'channels' => new List<Object>{
                        new Map<String, Object>{
                            'channelType' => CONSENT_CHANNEL_TYPE,
                            'consent'     => mapConsent(marketingConsent),
                            'channelCode' => CONSENT_CHANNEL_CODE,
                            'consentAbbr' => CONSENT_CONSENT_ABBR
                        }
                    }
                }
            }
        };
    }

    private static String mapConsent(String marketingConsent) {
        return 'Yes'.equalsIgnoreCase(marketingConsent) ? 'yes' : 'no';
    }

    // ─────────────────────────────────────────────────────────────
    // Payload building (V2 schema)
    // ─────────────────────────────────────────────────────────────

    private static Map<String, Object> buildPayload(EditCustomerRequest req, Account acc) {
        Boolean isPerson = req.isPersonAccount == null ? true : req.isPersonAccount;

        Map<String, Object> attributes = new Map<String, Object>();
        attributes.put('brand', BRAND);
        attributes.put('customerType', isPerson ? 'INDIVIDUAL' : 'ORGANISATION');

        if (isPerson) {
            Map<String, Object> individual = buildIndividual(req, acc);
            if (!individual.isEmpty()) attributes.put('individual', individual);
        } else {
            Map<String, Object> organisation = buildOrganisation(req, acc);
            if (!organisation.isEmpty()) attributes.put('organisation', organisation);
        }

        Map<String, Object> contactMethods = buildContactMethods(req);
        if (!contactMethods.isEmpty()) attributes.put('contactMethods', contactMethods);

        if (req.addressChanged == true) {
            Map<String, Object> addresses = buildAddresses(req);
            if (!addresses.isEmpty()) attributes.put('addresses', addresses);
        }

        if (req.membershipChanged == true) {
            List<Object> memberships = buildMemberships(req);
            if (memberships != null) attributes.put('memberships', memberships);
        }

        attributes.put('audit', new Map<String, Object>{
            'lastModifiedBy'       => getCurrentUserUNumber(),
            'sourceSystemModified' => 'CRM'
        });

        return new Map<String, Object>{
            'data' => new Map<String, Object>{
                'id'         => acc.SourceSystemId__c,
                'attributes' => attributes
            }
        };
    }

    private static Map<String, Object> buildIndividual(EditCustomerRequest req, Account acc) {
        Map<String, Object> individual = new Map<String, Object>();

        // Name block — include if name, title, OR preferredName changed
        if (req.nameChanged == true || req.titleChanged == true || req.preferredNameChanged == true) {
            Map<String, Object> name = new Map<String, Object>();
            // CMDM requires firstName + lastName when name block is sent
            name.put('firstName', String.isNotBlank(req.firstName) ? req.firstName : acc.FirstName);
            name.put('lastName',  String.isNotBlank(req.lastName)  ? req.lastName  : acc.LastName);
            if (String.isNotBlank(req.middleName)) name.put('middleName', req.middleName);
            if (req.titleChanged == true && String.isNotBlank(req.title)) {
                name.put('title', req.title);
            }
            // Preferred Name saves to SF locally only — NOT sent to CMDM (per spec)
            individual.put('name', name);
        }

        if (req.dobChanged == true && req.birthdate != null) {
            individual.put('dateOfBirth', new Map<String, Object>{
                'detail' => String.valueOf(req.birthdate)
            });
        }

        if (req.genderChanged == true && String.isNotBlank(req.gender)) {
            individual.put('gender', new Map<String, Object>{
                'detail' => req.gender.toUpperCase()
            });
        }

        return individual;
    }

    private static Map<String, Object> buildOrganisation(EditCustomerRequest req, Account acc) {
        Map<String, Object> organisation = new Map<String, Object>();
        if (req.nameChanged == true) {
            String orgName = String.isNotBlank(req.accountName) ? req.accountName : acc.Name;
            if (String.isNotBlank(orgName)) {
                organisation.put('name', new Map<String, Object>{
                    'organisationName' => orgName
                });
            }
        }
        return organisation;
    }

    private static Map<String, Object> buildContactMethods(EditCustomerRequest req) {
        Map<String, Object> contactMethods = new Map<String, Object>();
        if (req.mobileChanged == true && String.isNotBlank(req.mobile)) {
            contactMethods.put('mobilePhone', new Map<String, Object>{
                'detail' => req.mobile
            });
        }
        if (req.emailChanged == true && String.isNotBlank(req.email)) {
            contactMethods.put('email', new Map<String, Object>{
                'detail' => req.email
            });
        }
        return contactMethods;
    }

    private static Map<String, Object> buildAddresses(EditCustomerRequest req) {
        Map<String, Object> postal = new Map<String, Object>();

        // addressLine1: streetNumber + streetName + streetType
        List<String> line1Parts = new List<String>();
        if (String.isNotBlank(req.streetNumber)) line1Parts.add(req.streetNumber);
        if (String.isNotBlank(req.streetName))   line1Parts.add(req.streetName);
        if (String.isNotBlank(req.streetType))   line1Parts.add(req.streetType);
        if (!line1Parts.isEmpty()) {
            postal.put('addressLine1', String.join(line1Parts, ' '));
        }

        // addressLine2: building + unit/level (if any)
        List<String> line2Parts = new List<String>();
        if (String.isNotBlank(req.buildingName)) line2Parts.add(req.buildingName);
        if (String.isNotBlank(req.unitType) && String.isNotBlank(req.unitNumber)) {
            line2Parts.add(req.unitType + ' ' + req.unitNumber);
        }
        if (String.isNotBlank(req.levelType) && String.isNotBlank(req.levelNumber)) {
            line2Parts.add(req.levelType + ' ' + req.levelNumber);
        }
        if (!line2Parts.isEmpty()) {
            postal.put('addressLine2', String.join(line2Parts, ', '));
        }

        // V2 has separate locality + townCity fields (unlike V3 which only accepts locality)
        // locality = suburb (e.g. "Owhata"), townCity = city (e.g. "Rotorua")
        if (String.isNotBlank(req.locality)) postal.put('locality', req.locality);
        if (String.isNotBlank(req.townCity)) postal.put('townCity', req.townCity);

        if (String.isNotBlank(req.state))    postal.put('state', req.state);
        if (String.isNotBlank(req.postcode)) postal.put('postcode', req.postcode);

        String c = normaliseCountry(req.country);
        if (String.isNotBlank(c)) {
            postal.put('country', c);
            postal.put('countryCode', c);
        }

        Map<String, Object> result = new Map<String, Object>();
        if (!postal.isEmpty()) result.put('postalAddress', postal);
        return result;
    }

    /**
     * Build memberships array (V2 best guess — adjust if spec differs).
     * Structure follows V2's value-wrapping pattern: { detail: ... }
     *
     * Both number + start date should be provided together. If only one is set,
     * we send what we have.
     */
    private static List<Object> buildMemberships(EditCustomerRequest req) {
        Boolean hasNumber = String.isNotBlank(req.aaMembershipNumber);
        Boolean hasDate   = String.isNotBlank(req.aaMembershipStartDate);

        if (!hasNumber && !hasDate) {
            // Both removed → send empty array to clear
            return new List<Object>();
        }

        Map<String, Object> membership = new Map<String, Object>{
            'membershipType' => 'AA'
        };
        if (hasNumber) {
            membership.put('membershipNumber', new Map<String, Object>{
                'detail' => req.aaMembershipNumber
            });
        }
        if (hasDate) {
            membership.put('startDate', new Map<String, Object>{
                'detail' => req.aaMembershipStartDate
            });
        }
        return new List<Object>{ membership };
    }

    private static String combineLocality(String locality, String townCity) {
        Boolean hasLoc = String.isNotBlank(locality);
        Boolean hasCity = String.isNotBlank(townCity);
        if (!hasLoc && !hasCity) return null;
        if (hasLoc && !hasCity) return locality;
        if (!hasLoc && hasCity) return townCity;
        if (locality.trim().equalsIgnoreCase(townCity.trim())) return locality;
        return locality + ', ' + townCity;
    }

    private static String normaliseCountry(String c) {
        if (String.isBlank(c)) return null;
        String up = c.toUpperCase().trim();
        if (up == 'NEW ZEALAND') return 'NZ';
        if (up == 'AUSTRALIA') return 'AU';
        return up;
    }

    private static String parseError(String body, Integer status) {
        if (String.isBlank(body)) return 'CMDM V2 returned ' + status + ' with empty body';
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            if (parsed.containsKey('errors')) {
                List<Object> errors = (List<Object>) parsed.get('errors');
                if (!errors.isEmpty()) {
                    Map<String, Object> first = (Map<String, Object>) errors[0];
                    String title  = String.valueOf(first.get('title'));
                    String detail = String.valueOf(first.get('detail'));
                    return (title != null ? '[' + title + '] ' : '') + (detail != null ? detail : body);
                }
            }
            if (parsed.containsKey('message')) return String.valueOf(parsed.get('message'));
        } catch (Exception e) {
            // fall through
        }
        return 'HTTP ' + status + ': ' + body;
    }
    /**
     * Returns the current user's UNumber__c (preferred) or falls back to User Id.
     * Cached per transaction.
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
