/**
 * OpportunityLineItemTriggerTest
 * Covers all business rules enforced by the Opportunity Line Item trigger:
 *   - Discount > 20 blocked
 *   - Zero/null quantity blocked
 *   - Duplicate product blocked
 *   - Duplicate product update does not false-positive
 *   - Rollup on insert, update, delete
 *   - Bulk 200-record scenario
 */
@IsTest
private class OpportunityLineItemTriggerTest {

    // ─── Shared Setup ─────────────────────────────────────────────────────

    /**
     * Returns a ready-to-use pricebook entry so every test method doesn't
     * repeat the standard pricebook setup dance.
     */
    private static Map<String, Object> buildTestContext() {
        Account acc       = TestDataFactory.createAccount('Acme Corp');
        Opportunity opp   = TestDataFactory.createOpportunity(acc.Id, 'Deal 1', Date.today().addDays(30));
        Product2 prod     = TestDataFactory.createProduct('Widget Pro');
        PricebookEntry pbe = TestDataFactory.createPricebookEntry(prod.Id, 100);

        // Associate Opportunity with Standard Pricebook
        opp.Pricebook2Id = Test.getStandardPricebookId();
        update opp;

        return new Map<String, Object>{
            'opp'  => opp,
            'prod' => prod,
            'pbe'  => pbe
        };
    }

    // ─── Discount Validation ──────────────────────────────────────────────

    @IsTest
    static void testDiscountOver20BlocksSave() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId    = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 2,
            UnitPrice        = 100,
            Discount         = 25
        );

        Test.startTest();
        try {
            insert oli;
            Assert.fail('Expected DmlException for discount > 20');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains(OpportunityLineItemService.MSG_DISCOUNT_APPROVAL),
                'Wrong error message: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testDiscountAt20IsAllowed() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId    = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100,
            Discount         = 20  // boundary — exactly 20 should succeed
        );

        Test.startTest();
        insert oli;  // no exception expected
        Test.stopTest();

        Assert.isNotNull(oli.Id, 'OLI should have been inserted');
    }

    // ─── Quantity Validation ──────────────────────────────────────────────

    @IsTest
    static void testZeroQuantityBlocksSave() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId    = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 0,
            UnitPrice        = 100,
            Discount         = 0
        );

        Test.startTest();
        try {
            insert oli;
            Assert.fail('Expected DmlException for zero quantity');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains(OpportunityLineItemService.MSG_ZERO_QTY),
                'Wrong error message: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ─── Duplicate Product Validation ────────────────────────────────────

    @IsTest
    static void testDuplicateProductBlocksInsert() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        // Insert first line item successfully
        TestDataFactory.createLineItem(opp.Id, pbe.Id, 1, 100, 0);

        // Attempt to insert same product again
        OpportunityLineItem duplicate = new OpportunityLineItem(
            OpportunityId    = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 2,
            UnitPrice        = 100,
            Discount         = 0
        );

        Test.startTest();
        try {
            insert duplicate;
            Assert.fail('Expected DmlException for duplicate product');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains(OpportunityLineItemService.MSG_DUPLICATE_PRODUCT),
                'Wrong error message: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testDuplicateProductAllowsUpdate() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        OpportunityLineItem oli = TestDataFactory.createLineItem(opp.Id, pbe.Id, 1, 100, 0);

        // Updating the existing OLI should not trigger a duplicate error
        oli.Quantity = 5;

        Test.startTest();
        update oli;  // no exception expected
        Test.stopTest();

        OpportunityLineItem updated = [SELECT Quantity FROM OpportunityLineItem WHERE Id = :oli.Id];
        Assert.areEqual(5, updated.Quantity, 'Quantity should have been updated to 5');
    }

    // ─── Rollup Tests ─────────────────────────────────────────────────────

    @IsTest
    static void testRollupOnInsert() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        // 100 * 2 * 10% = 20
        Test.startTest();
        TestDataFactory.createLineItem(opp.Id, pbe.Id, 2, 100, 10);
        Test.stopTest();

        Opportunity result = [SELECT Total_Discount_Amount__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual(20, result.Total_Discount_Amount__c, 'Rollup should be 20');
    }

    @IsTest
    static void testRollupOnUpdate() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        OpportunityLineItem oli = TestDataFactory.createLineItem(opp.Id, pbe.Id, 2, 100, 10);

        // Change discount to 15% → 100 * 2 * 15% = 30
        oli.Discount = 15;

        Test.startTest();
        update oli;
        Test.stopTest();

        Opportunity result = [SELECT Total_Discount_Amount__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual(30, result.Total_Discount_Amount__c, 'Rollup should be 30 after update');
    }

    @IsTest
    static void testRollupOnDelete() {
        Map<String, Object> ctx = buildTestContext();
        Opportunity opp         = (Opportunity) ctx.get('opp');
        PricebookEntry pbe      = (PricebookEntry) ctx.get('pbe');

        OpportunityLineItem oli = TestDataFactory.createLineItem(opp.Id, pbe.Id, 2, 100, 10);

        Test.startTest();
        delete oli;
        Test.stopTest();

        Opportunity result = [SELECT Total_Discount_Amount__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual(0, result.Total_Discount_Amount__c, 'Rollup should be 0 after delete');
    }

    // ─── Bulk Test ────────────────────────────────────────────────────────

    @IsTest
    static void testBulk200RecordsAcross10Opportunities() {
        Account acc = TestDataFactory.createAccount('Bulk Corp');

        // Create 10 opportunities and 20 unique products
        List<Opportunity> opps   = new List<Opportunity>();
        List<Product2>    prods  = new List<Product2>();
        for (Integer i = 0; i < 10; i++) {
            opps.add(new Opportunity(
                AccountId  = acc.Id,
                Name       = 'Bulk Deal ' + i,
                CloseDate  = Date.today().addDays(30),
                StageName  = 'Prospecting',
                Pricebook2Id = Test.getStandardPricebookId()
            ));
        }
        insert opps;
        for (Integer i = 0; i < 20; i++) {
            prods.add(new Product2(Name = 'Bulk Product ' + i, IsActive = true));
        }
        insert prods;

        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 p : prods) {
            pbes.add(new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id   = p.Id,
                UnitPrice    = 50,
                IsActive     = true
            ));
        }
        insert pbes;

        // Build 200 OLIs: 10 opps × 20 products, valid discount (10%)
        List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
        for (Integer o = 0; o < 10; o++) {
            for (Integer p = 0; p < 20; p++) {
                olis.add(new OpportunityLineItem(
                    OpportunityId    = opps[o].Id,
                    PricebookEntryId = pbes[p].Id,
                    Quantity         = 1,
                    UnitPrice        = 50,
                    Discount         = 10
                ));
            }
        }

        Test.startTest();
        insert olis;
        Test.stopTest();

        // Each Opp has 20 OLIs: 50 * 1 * 10% = 5 each → 100 total per Opp
        for (Opportunity opp : [
            SELECT Total_Discount_Amount__c FROM Opportunity WHERE Id IN :opps
        ]) {
            Assert.areEqual(100, opp.Total_Discount_Amount__c,
                'Each Opp should have Total_Discount_Amount__c = 100');
        }
    }
}
