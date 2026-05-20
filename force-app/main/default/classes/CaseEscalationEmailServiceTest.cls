/**
 * CaseEscalationEmailServiceTest
 * Covers Scenario 06 – Experience Cloud Escalation Email (Platform Event path).
 *
 * Test strategy:
 *  - Platform Events published in a test context are delivered synchronously
 *    inside Test.startTest() / Test.stopTest(), so the event handler (and its
 *    email sends) execute within the same test transaction.
 *  - OrgWideEmailAddress cannot be created or queried in a test context because
 *    it is a setup object. CaseEscalationEventHandler therefore degrades
 *    gracefully (returns without throwing) when no matching address is found.
 *    Tests verify the absence of exceptions, not Messaging.sendEmail() call
 *    counts, for that path.
 *  - CaseEscalationEmailService.processed is reset before every test to prevent
 *    state leakage between test methods.
 */
@IsTest
private class CaseEscalationEmailServiceTest {

    private static final String STATUS_ESCALATED = 'Escalated';
    private static final String STATUS_NEW       = 'New';
    private static final String PRIORITY_HIGH    = 'High';
    private static final String PRIORITY_MEDIUM  = 'Medium';

    private static void resetService() {
        CaseEscalationEmailService.processed = new Set<Id>();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AC1 — Status changes to Escalated + Priority High → event published,
    //        handler executes without exception.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void statusEscalated_highPriority_eventPublished() {
        resetService();
        Case c = TestDataFactory.createCase('Escalation Email Case');

        Test.startTest();
        update new Case(Id = c.Id, Status = STATUS_ESCALATED, Priority = PRIORITY_HIGH);
        Test.stopTest(); // delivers platform event synchronously

        Case result = [SELECT Status, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals(STATUS_ESCALATED, result.Status);
        System.assertEquals(PRIORITY_HIGH,    result.Priority);
        System.assert(
            CaseEscalationEmailService.processed.contains(c.Id),
            'Case Id must be in processed set after event publish'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AC2 — Status=Escalated but Priority is NOT High → no event published.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void statusEscalated_notHighPriority_noEvent() {
        resetService();
        Case c = TestDataFactory.createCase('Medium Priority Case');

        Test.startTest();
        update new Case(Id = c.Id, Status = STATUS_ESCALATED, Priority = PRIORITY_MEDIUM);
        Test.stopTest();

        System.assert(
            !CaseEscalationEmailService.processed.contains(c.Id),
            'Case Id must NOT be in processed set when Priority is not High'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AC3 — Case was already Escalated → re-save must not publish a second event.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void alreadyEscalated_noSecondEvent() {
        resetService();
        Case c = TestDataFactory.buildCase('Already Escalated');
        c.Status   = STATUS_ESCALATED;
        c.Priority = PRIORITY_HIGH;
        insert c;

        // Reset after insert so the test starts clean
        resetService();

        Test.startTest();
        update new Case(Id = c.Id, Subject = 'Subject updated only');
        Test.stopTest();

        System.assert(
            !CaseEscalationEmailService.processed.contains(c.Id),
            'No event should fire when Status was already Escalated before the save'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AC4 — Status is not Escalated → no event published.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void statusNotEscalated_noEvent() {
        resetService();
        Case c = TestDataFactory.createCase('Non-Escalated Case');

        Test.startTest();
        update new Case(Id = c.Id, Subject = 'Updated subject');
        Test.stopTest();

        System.assert(
            !CaseEscalationEmailService.processed.contains(c.Id),
            'No event should fire when Status is not Escalated'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AC5 — Recursion guard: same Case updated twice in one transaction.
    //        Only one event must be published.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void recursionGuard_singleEventPerCase() {
        resetService();
        Case c = TestDataFactory.createCase('Recursion Guard Case');

        Test.startTest();
        update new Case(Id = c.Id, Status = STATUS_ESCALATED, Priority = PRIORITY_HIGH);
        // Second save — processed set must prevent a second event.
        update new Case(Id = c.Id, Subject = 'Re-saved');
        Test.stopTest();

        System.assert(
            CaseEscalationEmailService.processed.contains(c.Id),
            'Case Id must be in processed set'
        );
        // Exactly one entry per Case regardless of re-saves
        System.assertEquals(1, CaseEscalationEmailService.processed.size(),
            'Processed set must contain exactly one entry for this Case');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AC6 — Bulk: 200 Cases, half escalated → only 100 Ids in processed set.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void bulk_onlyEscalatedCasesPublishEvents() {
        resetService();
        Integer ESCALATED_COUNT = 100;
        Integer NORMAL_COUNT    = 100;

        List<Case> allCases = new List<Case>();
        for (Integer i = 0; i < ESCALATED_COUNT + NORMAL_COUNT; i++) {
            allCases.add(TestDataFactory.buildCase('Bulk Case ' + i));
        }
        insert allCases;

        List<Case> toUpdate = new List<Case>();
        for (Integer i = 0; i < ESCALATED_COUNT; i++) {
            toUpdate.add(new Case(
                Id       = allCases[i].Id,
                Status   = STATUS_ESCALATED,
                Priority = PRIORITY_HIGH
            ));
        }
        for (Integer i = ESCALATED_COUNT; i < allCases.size(); i++) {
            toUpdate.add(new Case(
                Id      = allCases[i].Id,
                Subject = 'Normal update ' + i
            ));
        }

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        System.assertEquals(ESCALATED_COUNT,
            CaseEscalationEmailService.processed.size(),
            'Exactly 100 Case Ids should be in the processed set');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CaseEscalationEventHandler — graceful degradation when OrgWideEmailAddress
    // is absent (which is always the case in test context — setup object).
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void eventHandler_missingOrgWideAddress_noException() {
        List<Case_Escalation_Event__e> events =
            new List<Case_Escalation_Event__e>{
                new Case_Escalation_Event__e(
                    Case_Id__c     = '5000000000000000',
                    Case_Number__c = '00001000',
                    Subject__c     = 'Test Subject'
                )
            };

        Test.startTest();
        try {
            CaseEscalationEventHandler.handleEvents(events);
            System.assert(true, 'Handler must not throw when org-wide address is absent');
        } catch (Exception ex) {
            System.assert(false, 'Unexpected exception: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CaseEscalationEventHandler — empty list must not throw.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void eventHandler_emptyList_noException() {
        Test.startTest();
        try {
            CaseEscalationEventHandler.handleEvents(
                new List<Case_Escalation_Event__e>()
            );
            System.assert(true, 'Empty event list must be handled gracefully');
        } catch (Exception ex) {
            System.assert(false, 'Unexpected exception: ' + ex.getMessage());
        }
        Test.stopTest();
    }
}
