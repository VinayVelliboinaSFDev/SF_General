/**
 * CaseSLAEscalationServiceTest
 * Covers Scenario 05 – Case SLA Escalation.
 *
 * Test strategy:
 *  - @TestSetup creates a TEST-ONLY escalation queue (Group + QueueSObject).
 *    A separate DeveloperName ('Test_Case_Escl_Queue') is used intentionally
 *    to avoid DUPLICATE_DEVELOPER_NAME collisions with the metadata-deployed
 *    'Case_Escalation_Queue' that already exists in the org.
 *  - Each test method calls configureService() to point the service at the
 *    test queue and reset per-transaction static state. Static variables in
 *    Apex reset between test method executions, so this is needed each time.
 *  - Each @IsTest method covers exactly one acceptance criterion.
 *  - Bulk test uses 200 Cases (> one trigger batch) to exercise governor limits.
 */
@IsTest
private class CaseSLAEscalationServiceTest {

    // Developer name used ONLY in tests — distinct from the production queue
    private static final String TEST_QUEUE_DEV_NAME = 'Test_Case_Escl_Queue';

    private static final DateTime PAST_DATE   = DateTime.now().addDays(-1);
    private static final DateTime FUTURE_DATE = DateTime.now().addDays(30);

    // ── One-time setup: create the test queue ────────────────────────────────

    @TestSetup
    static void makeData() {
        Group q = new Group(
            Name          = 'Test Case Escalation Queue',
            DeveloperName = TEST_QUEUE_DEV_NAME,
            Type          = 'Queue'
        );
        insert q;

        // Associate the queue with Case so Cases can be owned by it
        QueueSObject qso = new QueueSObject(QueueId = q.Id, SobjectType = 'Case');
        insert qso;
    }

    // ── Per-test helper ──────────────────────────────────────────────────────

    /**
     * Resets all service-level static state and redirects the service to the
     * test queue. Must be called at the START of every test method because
     * static variables are reset between test method executions.
     */
    private static void configureService() {
        CaseSLAEscalationService.escalationQueueDevName = TEST_QUEUE_DEV_NAME;
        CaseSLAEscalationService.transactionQueueId     = null;
        CaseSLAEscalationService.processed              = new Set<Id>();
    }

    private static Id getTestQueueId() {
        return [SELECT Id FROM Group WHERE DeveloperName = :TEST_QUEUE_DEV_NAME LIMIT 1].Id;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Acceptance Criterion 1
    // SLA date updated to a FUTURE date → no escalation, Case stays in place.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void slaExtendedToFuture_noEscalation() {
        configureService();
        Case c = TestDataFactory.createCase('Future SLA Case');
        Id testQueueId = getTestQueueId();

        Test.startTest();
        c.SLA_Due_Date__c = FUTURE_DATE;
        update c;
        Test.stopTest();

        Case result = [SELECT OwnerId, Status FROM Case WHERE Id = :c.Id];
        System.assertNotEquals(testQueueId, result.OwnerId,
            'Case should not be moved to escalation queue when SLA is extended to the future');
        System.assertNotEquals('Escalated', result.Status,
            'Status must not change when SLA date is set to a future value');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Acceptance Criterion 2
    // SLA date updated to a PAST date → Case must be escalated.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void slaOverdue_caseEscalated() {
        configureService();
        Case c = TestDataFactory.createCase('Overdue SLA Case');
        Id testQueueId = getTestQueueId();

        Test.startTest();
        c.SLA_Due_Date__c = PAST_DATE;
        update c;
        Test.stopTest();

        Case result = [SELECT OwnerId, Priority, Status, IsEscalated FROM Case WHERE Id = :c.Id];
        System.assertEquals(testQueueId, result.OwnerId,
            'Case must be reassigned to the escalation queue when SLA due date is in the past');
        System.assertEquals('High', result.Priority,
            'Priority must be set to High on escalation');
        System.assertEquals('Escalated', result.Status,
            'Status must be set to Escalated');
        System.assertEquals(true, result.IsEscalated,
            'IsEscalated must be true');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Acceptance Criterion 3
    // Case already in the escalation queue → must not be re-assigned.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void caseAlreadyInEscalationQueue_notReassigned() {
        configureService();
        Id testQueueId = getTestQueueId();

        Case c = TestDataFactory.buildCase('Already Escalated Case');
        c.OwnerId     = testQueueId;
        c.Status      = 'Escalated';
        c.Priority    = 'High';
        c.IsEscalated = true;
        insert c;

        Test.startTest();
        c.SLA_Due_Date__c = PAST_DATE;
        update c;
        Test.stopTest();

        Case result = [SELECT OwnerId, Status, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals(testQueueId, result.OwnerId,
            'OwnerId must remain the escalation queue — no duplicate reassignment');
        System.assertEquals('Escalated', result.Status,
            'Status must remain Escalated');
        System.assertEquals('High', result.Priority,
            'Priority must remain High');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Acceptance Criterion 4 (bulk)
    // 200 Cases simultaneously updated — only overdue ones escalated.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void bulkUpdate_onlyOverdueCasesEscalated() {
        configureService();
        Integer OVERDUE_COUNT = 100;
        Integer FUTURE_COUNT  = 100;
        Id testQueueId = getTestQueueId();

        List<Case> allCases = new List<Case>();
        for (Integer i = 0; i < OVERDUE_COUNT + FUTURE_COUNT; i++) {
            allCases.add(TestDataFactory.buildCase('Bulk Case ' + i));
        }
        insert allCases;

        List<Case> toUpdate = new List<Case>();
        for (Integer i = 0; i < OVERDUE_COUNT; i++) {
            toUpdate.add(new Case(Id = allCases[i].Id, SLA_Due_Date__c = PAST_DATE));
        }
        for (Integer i = OVERDUE_COUNT; i < allCases.size(); i++) {
            toUpdate.add(new Case(Id = allCases[i].Id, SLA_Due_Date__c = FUTURE_DATE));
        }

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        Set<Id> overdueIds = new Set<Id>();
        for (Integer i = 0; i < OVERDUE_COUNT; i++) {
            overdueIds.add(allCases[i].Id);
        }
        for (Case result : [SELECT OwnerId, Status FROM Case WHERE Id IN :overdueIds]) {
            System.assertEquals(testQueueId, result.OwnerId,
                'Overdue Case must be in the escalation queue');
            System.assertEquals('Escalated', result.Status,
                'Overdue Case status must be Escalated');
        }

        Set<Id> futureIds = new Set<Id>();
        for (Integer i = OVERDUE_COUNT; i < allCases.size(); i++) {
            futureIds.add(allCases[i].Id);
        }
        for (Case result : [SELECT OwnerId FROM Case WHERE Id IN :futureIds]) {
            System.assertNotEquals(testQueueId, result.OwnerId,
                'Future-SLA Case must not be moved to the escalation queue');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Acceptance Criterion 5
    // Closed Cases must not be escalated regardless of SLA date.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void closedCase_notEscalated() {
        configureService();
        Id testQueueId = getTestQueueId();

        Case c = TestDataFactory.buildCase('Closed Case');
        c.Status = 'Closed';
        insert c;

        Test.startTest();
        c.SLA_Due_Date__c = PAST_DATE;
        update c;
        Test.stopTest();

        Case result = [SELECT OwnerId, Status FROM Case WHERE Id = :c.Id];
        System.assertNotEquals(testQueueId, result.OwnerId,
            'Closed Case must not be reassigned');
        System.assertEquals('Closed', result.Status,
            'Status must remain Closed');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Acceptance Criterion 7
    // Recursion guard: service-triggered DML must not cause a second
    // escalation cycle for the same Case within the same transaction.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void recursionGuard_noDoubleUpdate() {
        configureService();
        Id testQueueId = getTestQueueId();
        Case c = TestDataFactory.createCase('Recursion Guard Case');

        Test.startTest();
        c.SLA_Due_Date__c = PAST_DATE;
        update c; // First update — triggers escalation, marks Id in processed set

        // Simulate a re-save of the same Case (e.g., by an automation rule).
        // Use a targeted SObject to avoid overwriting fields the service set
        // (such as Status='Escalated') with stale values held in the c variable.
        // The static processed set must prevent a second escalation cycle.
        Case resave = new Case(
            Id              = c.Id,
            Subject         = 'Re-saved by Automation',
            SLA_Due_Date__c = PAST_DATE.addDays(-1) // still overdue, different value
        );
        update resave;
        Test.stopTest();

        Case result = [SELECT OwnerId, Status, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals(testQueueId, result.OwnerId,
            'Case must still be in the escalation queue after the second save');
        System.assertEquals('Escalated', result.Status,
            'Status must remain Escalated');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Edge case: SLA_Due_Date__c not changed
    // A save with no SLA date change must not trigger escalation.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void slaFieldUnchanged_noEscalation() {
        configureService();
        Id testQueueId = getTestQueueId();

        Case c = TestDataFactory.buildCase('No SLA Change Case');
        c.SLA_Due_Date__c = PAST_DATE;
        insert c;

        Id ownerBefore = [SELECT OwnerId FROM Case WHERE Id = :c.Id].OwnerId;

        Test.startTest();
        c.Subject = 'Only Subject Changed';
        update c; // SLA_Due_Date__c unchanged
        Test.stopTest();

        Case result = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(ownerBefore, result.OwnerId,
            'Owner must not change when SLA_Due_Date__c is unchanged');
        System.assertNotEquals(testQueueId, result.OwnerId,
            'Case must not be escalated when only a non-SLA field changes');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Edge case: SLA_Due_Date__c cleared to null
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void slaClearedToNull_noEscalation() {
        configureService();
        Id testQueueId = getTestQueueId();

        Case c = TestDataFactory.buildCase('Null SLA Case');
        c.SLA_Due_Date__c = FUTURE_DATE;
        insert c;

        Test.startTest();
        c.SLA_Due_Date__c = null;
        update c;
        Test.stopTest();

        Case result = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertNotEquals(testQueueId, result.OwnerId,
            'Clearing SLA_Due_Date__c to null must not trigger escalation');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Coverage: empty handler stubs for unused trigger contexts
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void handlerEmptyContexts_noException() {
        CaseTriggerHandler handler = new CaseTriggerHandler();
        handler.beforeInsert(new List<SObject>());
        handler.beforeUpdate(new List<SObject>(), new Map<Id, SObject>());
        handler.beforeDelete(new List<SObject>());
        handler.afterInsert(new List<SObject>(), new Map<Id, SObject>());
        handler.afterDelete(new List<SObject>(), new Map<Id, SObject>());
        handler.afterUndelete(new List<SObject>());
        System.assert(true, 'Empty handler stubs must not throw');
    }
}
