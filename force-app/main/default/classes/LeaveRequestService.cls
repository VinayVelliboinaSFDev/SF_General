/**
 * LeaveRequestService
 * Business logic for Leave_Request__c records.
 * Handles balance validation, overlap detection, balance decrement after approval,
 * and the status-change routing that fires when an Approval Process finalises.
 */
public class LeaveRequestService {

    @TestVisible private static final String MSG_INSUFFICIENT_BALANCE =
        'Insufficient leave balance. Available: {0} day(s). Requested: {1} day(s).';
    @TestVisible private static final String MSG_OVERLAP =
        'Overlaps with an existing leave from {0} to {1}.';

    // ─── Before Insert ────────────────────────────────────────────────────

    /**
     * Blocks save when the requested days exceed the employee's balance.
     * Reads employee records in a single SOQL query for the whole batch.
     *
     * @param newList  Trigger.new
     */
    public static void validateBalance(List<Leave_Request__c> newList) {
        Set<Id> empIds = new Set<Id>();
        for (Leave_Request__c lr : newList) {
            empIds.add(lr.Employee__c);
        }

        Map<Id, Employee__c> empMap = new Map<Id, Employee__c>([
            SELECT Id, Leave_Balance__c FROM Employee__c WHERE Id IN :empIds
        ]);

        for (Leave_Request__c lr : newList) {
            Employee__c emp = empMap.get(lr.Employee__c);
            if (emp == null) continue;

            Decimal balance   = emp.Leave_Balance__c != null ? emp.Leave_Balance__c : 0;
            Decimal requested = lr.Leave_Days__c     != null ? lr.Leave_Days__c     : 0;

            if (requested > balance) {
                lr.addError(
                    String.format(MSG_INSUFFICIENT_BALANCE,
                        new List<Object>{ balance, requested })
                );
            }
        }
    }

    /**
     * Detects date-range overlaps with existing Approved or Pending Approval leaves
     * for the same employee. Instead of blocking, sets Status__c = 'Rejected' and
     * populates Rejection_Reason__c so the attempt is auditable.
     *
     * Overlap condition: NOT (new.End < existing.Start OR new.Start > existing.End)
     *
     * @param newList  Trigger.new
     */
    public static void detectAndRejectOverlaps(List<Leave_Request__c> newList) {
        Set<Id>   empIds      = new Set<Id>();
        Date      minStart    = null;
        Date      maxEnd      = null;

        for (Leave_Request__c lr : newList) {
            if (lr.Status__c == 'Rejected') continue; // skip already-rejected records
            empIds.add(lr.Employee__c);
            if (minStart == null || lr.Start_Date__c < minStart) minStart = lr.Start_Date__c;
            if (maxEnd   == null || lr.End_Date__c   > maxEnd)   maxEnd   = lr.End_Date__c;
        }

        if (empIds.isEmpty()) return;

        // Broad date filter first to minimise rows returned, then check per-record
        Map<Id, List<Leave_Request__c>> existingByEmp = new Map<Id, List<Leave_Request__c>>();
        for (Leave_Request__c existing : [
            SELECT Id, Employee__c, Start_Date__c, End_Date__c, Status__c
            FROM   Leave_Request__c
            WHERE  Employee__c IN :empIds
              AND  Status__c IN ('Approved', 'Pending Approval')
              AND  Start_Date__c <= :maxEnd
              AND  End_Date__c   >= :minStart
        ]) {
            if (!existingByEmp.containsKey(existing.Employee__c)) {
                existingByEmp.put(existing.Employee__c, new List<Leave_Request__c>());
            }
            existingByEmp.get(existing.Employee__c).add(existing);
        }

        for (Leave_Request__c lr : newList) {
            if (lr.Status__c == 'Rejected') continue;
            List<Leave_Request__c> conflicts = existingByEmp.get(lr.Employee__c);
            if (conflicts == null) continue;

            for (Leave_Request__c conflict : conflicts) {
                Boolean overlaps = !(lr.End_Date__c < conflict.Start_Date__c
                                     || lr.Start_Date__c > conflict.End_Date__c);
                if (overlaps) {
                    lr.Status__c          = 'Rejected';
                    lr.Rejection_Reason__c = String.format(MSG_OVERLAP,
                        new List<Object>{
                            conflict.Start_Date__c.format(),
                            conflict.End_Date__c.format()
                        });
                    break; // first overlap is enough
                }
            }
        }
    }

    // ─── After Approval / Status Change ──────────────────────────────────

    /**
     * Decrements Leave_Balance__c on Employee__c for all leave requests
     * whose Status__c just changed to 'Approved'.
     *
     * Called from LeaveRequestTriggerHandler.afterUpdate() and from
     * LeaveApprovalQueueable for auto-approved short leaves.
     *
     * @param approvedIds  IDs of Leave_Request__c records newly approved
     */
    public static void decrementBalance(List<Id> approvedIds) {
        if (approvedIds.isEmpty()) return;

        // Fetch leave days and employee for each approved request
        Map<Id, Decimal> daysByEmp = new Map<Id, Decimal>();
        for (Leave_Request__c lr : [
            SELECT Employee__c, Leave_Days__c
            FROM   Leave_Request__c
            WHERE  Id IN :approvedIds
        ]) {
            Decimal days = lr.Leave_Days__c != null ? lr.Leave_Days__c : 0;
            daysByEmp.put(
                lr.Employee__c,
                (daysByEmp.containsKey(lr.Employee__c) ? daysByEmp.get(lr.Employee__c) : 0) + days
            );
        }

        List<Employee__c> toUpdate = new List<Employee__c>();
        for (Employee__c emp : [
            SELECT Id, Leave_Balance__c FROM Employee__c WHERE Id IN :daysByEmp.keySet()
        ]) {
            emp.Leave_Balance__c = (emp.Leave_Balance__c != null ? emp.Leave_Balance__c : 0)
                                   - daysByEmp.get(emp.Id);
            toUpdate.add(emp);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
