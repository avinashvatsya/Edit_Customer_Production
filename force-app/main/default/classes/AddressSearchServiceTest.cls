@IsTest
private class AddressSearchServiceTest {

    // ============================================================
    // Single-line search
    // ============================================================

    @IsTest
    static void search_validQuery_returnsResults() {
        Test.setMock(HttpCalloutMock.class, new HopeweiserMock(200, singleLineMockBody(), null));

        Test.startTest();
        List<AddressSearchService.AddressSuggestion> results = 
            AddressSearchService.searchAddress('48 Shortland', false);
        Test.stopTest();

        Assert.areEqual(5, results.size());
        Assert.areEqual('NZ+PAF+1+1010SHO+@X1218705', results[0].addressKey);
        Assert.areEqual('48 Shortland St, Auckland Central, Auckland', results[0].summaryAddress);
        Assert.areEqual('1010', results[0].postcode);
        Assert.areEqual('NZ', results[0].country);
    }

    @IsTest
    static void search_shortQuery_returnsEmpty() {
        Assert.areEqual(0, AddressSearchService.searchAddress('48', false).size());
    }

    @IsTest
    static void search_blankQuery_returnsEmpty() {
        Assert.areEqual(0, AddressSearchService.searchAddress('', false).size());
        Assert.areEqual(0, AddressSearchService.searchAddress(null, false).size());
    }

    @IsTest
    static void search_500_throws() {
        Test.setMock(HttpCalloutMock.class, new HopeweiserMock(500, '{"error":"oops"}', null));
        try {
            Test.startTest();
            AddressSearchService.searchAddress('48 Shortland', false);
            Test.stopTest();
            Assert.fail('Should have thrown');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    // ============================================================
    // Broken-down lookup
    // ============================================================

    @IsTest
    static void brokenDown_validKey_returnsDetails() {
        Test.setMock(HttpCalloutMock.class, new HopeweiserMock(200, null, brokenDownMockBody()));

        Test.startTest();
        AddressSearchService.BrokenDownAddress result = 
            AddressSearchService.getBrokenDownAddress('NZ+CLOGIC+1+3010POH+@X0155888');
        Test.stopTest();

        Assert.areEqual('NZ+CLOGIC+1+3010POH+@X0155888', result.addressKey);
        Assert.areEqual('1', result.streetNumber);
        Assert.areEqual('Pohutukawa Dr', result.streetName);
        Assert.areEqual('Pohutukawa', result.streetNameNoSuffix);
        Assert.areEqual('Dr', result.streetType);
        Assert.areEqual('Owhata', result.locality);
        Assert.areEqual('Rotorua', result.townCity);
        Assert.areEqual('3010', result.postcode);
        Assert.areEqual('NZ', result.country);
        Assert.areEqual('NZ', result.state);
    }

    @IsTest
    static void brokenDown_blankKey_throws() {
        try {
            AddressSearchService.getBrokenDownAddress('');
            Assert.fail('Should have thrown');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void brokenDown_500_throws() {
        Test.setMock(HttpCalloutMock.class, new HopeweiserMock(500, null, '{"error":"oops"}'));
        try {
            Test.startTest();
            AddressSearchService.getBrokenDownAddress('ANYKEY');
            Test.stopTest();
            Assert.fail('Should have thrown');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    // ============================================================
    // Mock data
    // ============================================================

    private static String singleLineMockBody() {
        return '{' +
            '"responseTime":"2026-05-11T00:00:00.000+12:00",' +
            '"summaryAddresses":[' +
                '{"addressKey":"NZ+PAF+1+1010SHO+@X1218705","addressType":"URBAN",' +
                '"summaryAddress":"48 Shortland St, Auckland Central, Auckland",' +
                '"postcode":"1010","country":"NZ"},' +
                '{"addressKey":"NZ+PAF+1+8061SHO+@X0545091","addressType":"URBAN",' +
                '"summaryAddress":"48 Shortland St, Wainoni, Christchurch",' +
                '"postcode":"8061","country":"NZ"},' +
                '{"addressKey":"NZ+PAF+1+1010SHO+@X2529349","addressType":"URBAN",' +
                '"summaryAddress":"Level 1, 48 Shortland St, Auckland Central, Auckland",' +
                '"postcode":"1010","country":"NZ"},' +
                '{"addressKey":"NZ+PAF+1+1010SHO+@X2529350","addressType":"URBAN",' +
                '"summaryAddress":"Level 2, 48 Shortland St, Auckland Central, Auckland",' +
                '"postcode":"1010","country":"NZ"},' +
                '{"addressKey":"NZ+PAF+1+1010SHO+@X2529351","addressType":"URBAN",' +
                '"summaryAddress":"Level 3, 48 Shortland St, Auckland Central, Auckland",' +
                '"postcode":"1010","country":"NZ"}' +
            ']}';
    }

    private static String brokenDownMockBody() {
        return '{' +
            '"responseTime":"2026-05-15T05:54:47.530+10:00",' +
            '"operationResult":"SUCCESS",' +
            '"matchedAddress":{' +
                '"postcode":"3010","locality":"Owhata","townCity":"Rotorua",' +
                '"state":"NZ","country":"NZ",' +
                '"addressInBrokenDownForm":{' +
                    '"buildingName":"","streetNumber":"1","streetNumberLow":"1","streetNumberHigh":"",' +
                    '"streetNameNoSuffix":"Pohutukawa","streetDirection":"",' +
                    '"streetName":"Pohutukawa Dr","streetType":"Dr",' +
                    '"unitType":"","unitNumber":"","levelType":"","levelNumber":""' +
                '}' +
            '}}';
    }

    private class HopeweiserMock implements HttpCalloutMock {
        public Integer status;
        public String singleLineBody;
        public String brokenDownBody;

        public HopeweiserMock(Integer status, String singleLineBody, String brokenDownBody) {
            this.status = status;
            this.singleLineBody = singleLineBody;
            this.brokenDownBody = brokenDownBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(status);
            // Return different body depending on endpoint
            if (req.getEndpoint().contains('broken-down-form')) {
                resp.setBody(brokenDownBody != null ? brokenDownBody : singleLineBody);
            } else {
                resp.setBody(singleLineBody != null ? singleLineBody : brokenDownBody);
            }
            return resp;
        }
    }
}
