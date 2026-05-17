/**
 * LeaveRequestTriggerTest
 * Covers all business rules for Leave_Request__c:
 *   - Insufficient balance blocked
 *   - Overlapping leave auto-rejected with reason
 *   - Adjacent dates (no overlap) allowed
 *   - Short leave (≤ 2 days) auto-approved via Queueable
 *   - Long leave (> 2 days) submitted to approval path (mocked via Test.isRunningTest flag)
 *   - Balance decremented after status changes to Approved
 *   - Bulk: 50 requests across 5 employees
 */
@IsTest
private class LeaveRequestTriggerTest {

    // ─── Balance Validation ───────────────────────────────────────────────

    @IsTest
    static void testInsufficientBalanceBlocked() {
        Employee__c emp = TestDataFactory.createEmployee('Low Balance Emp', 3);

        Leave_Request__c lr = TestDataFactory.buildLeaveRequest(
            emp.Id,
            Date.today(),
            Date.today().addDays(4), // 5 days — exceeds balance of 3
            'Annual'
        );

        Test.startTest();
        try {
            insert lr;
            Assert.fail('Expected DmlException for insufficient balance');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains('Insufficient leave balance'),
                'Wrong error: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testSufficientBalanceAllowsInsert() {
        Employee__c emp = TestDataFactory.createEmployee('Good Balance Emp', 10);

        Test.startTest();
        Leave_Request__c lr = TestDataFactory.createLeaveRequest(
            emp.Id, Date.today(), Date.today().addDays(1), 'Annual'
        );
        Test.stopTest();

        Assert.isNotNull(lr.Id, 'Request should insert when balance is sufficient');
    }

    // ─── Overlap Detection ────────────────────────────────────────────────

    @IsTest
    static void testOverlappingLeaveAutoRejected() {
        Employee__c emp = TestDataFactory.createEmployee('Overlap Emp', 20);

        // Insert an approved leave: June 1–5
        Leave_Request__c approved = new Leave_Request__c(
            Employee__c   = emp.Id,
            Start_Date__c = Date.newInstance(2026, 6, 1),
            End_Date__c   = Date.newInstance(2026, 6, 5),
            Leave_Type__c = 'Annual',
            Status__c     = 'Approved'
        );
        insert approved;

        // New request overlaps: June 3–7
        Leave_Request__c newLr = TestDataFactory.buildLeaveRequest(
            emp.Id,
            Date.newInstance(2026, 6, 3),
            Date.newInstance(2026, 6, 7),
            'Annual'
        );

        Test.startTest();
        insert newLr;
        Test.stopTest();

        Leave_Request__c result = [
            SELECT Status__c, Rejection_Reason__c FROM Leave_Request__c WHERE Id = :newLr.Id
        ];
        Assert.areEqual('Rejected', result.Status__c, 'Overlapping request should be Rejected');
        Assert.isTrue(result.Rejection_Reason__c.contains('Overlaps'),
            'Rejection reason should mention overlap');
    }

    @IsTest
    static void testAdjacentDatesNotOverlapping() {
        Employee__c emp = TestDataFactory.createEmployee('Adjacent Emp', 20);

        // Approved: June 1–5
        insert new Leave_Request__c(
            Employee__c   = emp.Id,
            Start_Date__c = Date.newInstance(2026, 6, 1),
            End_Date__c   = Date.newInstance(2026, 6, 5),
            Leave_Type__c = 'Annual',
            Status__c     = 'Approved'
        );

        // New request: June 6–7 — immediately after, no overlap
        Leave_Request__c adjacent = TestDataFactory.buildLeaveRequest(
            emp.Id,
            Date.newInstance(2026, 6, 6),
            Date.newInstance(2026, 6, 7),
            'Annual'
        );

        Test.startTest();
        insert adjacent;
        Test.stopTest();

        Leave_Request__c result = [SELECT Status__c FROM Leave_Request__c WHERE Id = :adjacent.Id];
        Assert.areNotEqual('Rejected', result.Status__c, 'Adjacent dates should not be rejected');
    }

    // ─── Auto-Approve Short Leave ─────────────────────────────────────────

    @IsTest
    static void testShortLeaveAutoApprovedViaQueueable() {
        Employee__c emp = TestDataFactory.createEmployee('Short Leave Emp', 10);

        Leave_Request__c lr = TestDataFactory.buildLeaveRequest(
            emp.Id, Date.today(), Date.today().addDays(1), 'Annual' // 2 days
        );

        Test.startTest();
        insert lr;
        // stopTest() flushes the async Queueable
        Test.stopTest();

        Leave_Request__c result = [SELECT Status__c FROM Leave_Request__c WHERE Id = :lr.Id];
        Assert.areEqual('Approved', result.Status__c, '2-day leave should be auto-approved');

        Employee__c updatedEmp = [SELECT Leave_Balance__c FROM Employee__c WHERE Id = :emp.Id];
        Assert.areEqual(8, updatedEmp.Leave_Balance__c, 'Balance should be decremented by 2');
    }

    // ─── Long Leave → Approval Process path ─────────────────────────────

    @IsTest
    static void testLongLeaveRemainsInDraftOrPending() {
        Employee__c emp = TestDataFactory.createEmployee('Long Leave Emp', 20);

        Leave_Request__c lr = TestDataFactory.buildLeaveRequest(
            emp.Id, Date.today(), Date.today().addDays(4), 'Annual' // 5 days
        );

        Test.startTest();
        insert lr;
        Test.stopTest();

        // In test context, Approval.process() is skipped (guarded by Test.isRunningTest())
        // so Status stays 'Draft'. We verify balance was NOT yet decremented.
        Employee__c updatedEmp = [SELECT Leave_Balance__c FROM Employee__c WHERE Id = :emp.Id];
        Assert.areEqual(20, updatedEmp.Leave_Balance__c,
            'Balance should not change until Approval Process finalises');
    }

    // ─── Balance Decrement on Status Change ──────────────────────────────

    @IsTest
    static void testBalanceDecrementedOnManualApproval() {
        Employee__c emp = TestDataFactory.createEmployee('Manual Approve Emp', 20);

        // Insert a long-leave request — will stay Draft in test context
        Leave_Request__c lr = new Leave_Request__c(
            Employee__c   = emp.Id,
            Start_Date__c = Date.today(),
            End_Date__c   = Date.today().addDays(4), // 5 days
            Leave_Type__c = 'Annual',
            Status__c     = 'Pending Approval'
        );
        insert lr;

        // Simulate Approval Process finalising — set Status to Approved
        lr.Status__c = 'Approved';

        Test.startTest();
        update lr;
        Test.stopTest();

        Employee__c updatedEmp = [SELECT Leave_Balance__c FROM Employee__c WHERE Id = :emp.Id];
        Assert.areEqual(15, updatedEmp.Leave_Balance__c,
            'Balance should be decremented by 5 after approval');
    }

    // ─── Bulk Test ────────────────────────────────────────────────────────

    @IsTest
    static void testBulk50RequestsAcross5Employees() {
        List<Employee__c> emps = new List<Employee__c>();
        for (Integer i = 0; i < 5; i++) {
            emps.add(new Employee__c(Name = 'Bulk Emp ' + i, Leave_Balance__c = 50));
        }
        insert emps;

        List<Leave_Request__c> requests = new List<Leave_Request__c>();
        for (Integer e = 0; e < 5; e++) {
            for (Integer r = 0; r < 10; r++) {
                // Each request on a different date range to avoid overlaps
                Date startDt = Date.today().addDays(r * 3);
                Date endDt   = startDt.addDays(1); // 2-day leaves → will auto-approve
                requests.add(TestDataFactory.buildLeaveRequest(
                    emps[e].Id, startDt, endDt, 'Annual'
                ));
            }
        }

        Test.startTest();
        insert requests;
        Test.stopTest();

        // After Queueable flush: each short leave should be Approved
        Integer approvedCount = [
            SELECT COUNT() FROM Leave_Request__c
            WHERE Status__c = 'Approved' AND Id IN :requests
        ];
        Assert.areEqual(50, approvedCount, 'All 50 short-leave requests should be auto-approved');
    }
}
