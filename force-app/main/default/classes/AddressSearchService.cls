/**
 * AddressSearchService
 * 
 * Two-step Hopeweiser lookup via Suncorp Named Credential:
 *   1. searchAddress() — single-line typeahead (returns summary + addressKey)
 *   2. getBrokenDownAddress() — full structured address by addressKey
 */
public with sharing class AddressSearchService {

    // TODO (prod): replace BASE_URL with a Named Credential (e.g. 'callout:Suncorp_Address')
    // For now: hardcoded test URL — requires Remote Site Setting:
    //   Name: Suncorp_API_Test, URL: https://api-sys.test.suncorp.com.au
    private static final String BASE_URL          = 'https://api-sys.test.suncorp.com.au/stable3';
    private static final String SINGLE_LINE_PATH  = '/address-search-service/address/single-line-find/nz/v2';
    private static final String BROKEN_DOWN_PATH  = '/address-search-service/address/broken-down-form/nz/v2';
    private static final Integer DEFAULT_LIMIT    = 5;
    private static final Integer TIMEOUT_MS       = 10000;
    private static final Integer MIN_QUERY_LEN    = 7;

    // ============================================================
    // 1. Single-line typeahead
    // ============================================================

    @AuraEnabled(cacheable=false)
    public static List<AddressSuggestion> searchAddress(String query, Boolean isRiskAddress) {
        if (String.isBlank(query) || query.length() < MIN_QUERY_LEN) {
            return new List<AddressSuggestion>();
        }
        try {
            HttpResponse resp = doSingleLineCallout(query, isRiskAddress);
            if (resp.getStatusCode() == 200) {
                return parseSingleLineResponse(resp.getBody());
            }
            System.debug(LoggingLevel.WARN, 'Hopeweiser search non-200: ' 
                + resp.getStatusCode() + ' body=' + resp.getBody());
            throw new AuraHandledException('Address lookup unavailable (' 
                + resp.getStatusCode() + '). Use manual entry.');
        } catch (CalloutException ce) {
            System.debug(LoggingLevel.ERROR, 'Hopeweiser callout failed: ' + ce.getMessage());
            throw new AuraHandledException('Address service unreachable. Use manual entry.');
        }
    }

    private static HttpResponse doSingleLineCallout(String query, Boolean isRiskAddress) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + SINGLE_LINE_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('X-Request-Id', generateRequestId());
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'addressLine'   => query,
            'isRiskAddress' => isRiskAddress != null && isRiskAddress,
            'howMany'       => DEFAULT_LIMIT
        }));
        return new Http().send(req);
    }

    @TestVisible
    private static List<AddressSuggestion> parseSingleLineResponse(String jsonBody) {
        List<AddressSuggestion> results = new List<AddressSuggestion>();
        if (String.isBlank(jsonBody)) return results;

        Map<String, Object> respObj = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object> rawAddresses = (List<Object>) respObj.get('summaryAddresses');
        if (rawAddresses == null) return results;

        Integer idx = 0;
        for (Object rawAddr : rawAddresses) {
            Map<String, Object> addr = (Map<String, Object>) rawAddr;
            AddressSuggestion s = new AddressSuggestion();
            s.id              = 'addr-' + idx;
            s.addressKey      = stringValue(addr, 'addressKey');
            s.addressType     = stringValue(addr, 'addressType');
            s.summaryAddress  = stringValue(addr, 'summaryAddress');
            s.postcode        = stringValue(addr, 'postcode');
            s.country         = stringValue(addr, 'country');
            results.add(s);
            idx++;
        }
        return results;
    }

    // ============================================================
    // 2. Broken-down form lookup
    // ============================================================

    @AuraEnabled(cacheable=false)
    public static BrokenDownAddress getBrokenDownAddress(String addressKey) {
        if (String.isBlank(addressKey)) {
            throw new AuraHandledException('Address key is required.');
        }
        try {
            HttpResponse resp = doBrokenDownCallout(addressKey);
            if (resp.getStatusCode() == 200) {
                return parseBrokenDownResponse(resp.getBody(), addressKey);
            }
            System.debug(LoggingLevel.WARN, 'Hopeweiser broken-down non-200: ' 
                + resp.getStatusCode() + ' body=' + resp.getBody());
            throw new AuraHandledException('Could not load address details (' 
                + resp.getStatusCode() + '). Use manual entry.');
        } catch (CalloutException ce) {
            System.debug(LoggingLevel.ERROR, 'Broken-down callout failed: ' + ce.getMessage());
            throw new AuraHandledException('Address service unreachable. Use manual entry.');
        }
    }

    private static HttpResponse doBrokenDownCallout(String addressKey) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + BROKEN_DOWN_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('X-Request-Id', generateRequestId());
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'address' => new Map<String, Object>{ 'addressKey' => addressKey }
        }));
        return new Http().send(req);
    }

    @TestVisible
    private static BrokenDownAddress parseBrokenDownResponse(String jsonBody, String addressKey) {
        BrokenDownAddress result = new BrokenDownAddress();
        result.addressKey = addressKey;
        if (String.isBlank(jsonBody)) return result;

        Map<String, Object> respObj = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        Map<String, Object> matched = (Map<String, Object>) respObj.get('matchedAddress');
        if (matched == null) return result;

        result.postcode = stringValue(matched, 'postcode');
        result.locality = stringValue(matched, 'locality');
        result.townCity = stringValue(matched, 'townCity');
        result.state    = stringValue(matched, 'state');
        result.country  = stringValue(matched, 'country');

        Map<String, Object> brokenDown = (Map<String, Object>) matched.get('addressInBrokenDownForm');
        if (brokenDown == null) return result;

        result.buildingName       = stringValue(brokenDown, 'buildingName');
        result.streetNumber       = stringValue(brokenDown, 'streetNumber');
        result.streetNumberLow    = stringValue(brokenDown, 'streetNumberLow');
        result.streetNumberHigh   = stringValue(brokenDown, 'streetNumberHigh');
        result.streetName         = stringValue(brokenDown, 'streetName');
        result.streetNameNoSuffix = stringValue(brokenDown, 'streetNameNoSuffix');
        result.streetType         = stringValue(brokenDown, 'streetType');
        result.streetDirection    = stringValue(brokenDown, 'streetDirection');
        result.unitType           = stringValue(brokenDown, 'unitType');
        result.unitNumber         = stringValue(brokenDown, 'unitNumber');
        result.levelType          = stringValue(brokenDown, 'levelType');
        result.levelNumber        = stringValue(brokenDown, 'levelNumber');

        return result;
    }

    // ============================================================
    // Helpers
    // ============================================================

    private static String generateRequestId() {
        return 'sf-' + UserInfo.getOrganizationId() + '-' + Datetime.now().getTime();
    }

    private static String stringValue(Map<String, Object> m, String key) {
        if (m == null) return null;
        Object v = m.get(key);
        if (v == null) return null;
        String s = String.valueOf(v);
        return String.isBlank(s) ? null : s;
    }

    // ============================================================
    // Wire Types
    // ============================================================

    public class AddressSuggestion {
        @AuraEnabled public String id;
        @AuraEnabled public String addressKey;
        @AuraEnabled public String addressType;
        @AuraEnabled public String summaryAddress;
        @AuraEnabled public String postcode;
        @AuraEnabled public String country;
    }

    public class BrokenDownAddress {
        @AuraEnabled public String addressKey;
        @AuraEnabled public String postcode;
        @AuraEnabled public String locality;
        @AuraEnabled public String townCity;
        @AuraEnabled public String state;
        @AuraEnabled public String country;
        @AuraEnabled public String buildingName;
        @AuraEnabled public String streetNumber;
        @AuraEnabled public String streetNumberLow;
        @AuraEnabled public String streetNumberHigh;
        @AuraEnabled public String streetName;
        @AuraEnabled public String streetNameNoSuffix;
        @AuraEnabled public String streetType;
        @AuraEnabled public String streetDirection;
        @AuraEnabled public String unitType;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String levelType;
        @AuraEnabled public String levelNumber;
    }
}
