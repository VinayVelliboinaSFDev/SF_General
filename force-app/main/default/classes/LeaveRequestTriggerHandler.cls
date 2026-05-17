/**
 * LeaveRequestTriggerHandler
 * Routes Leave_Request__c trigger events to service/queueable classes.
 * Owns no business logic — purely a coordinator.
 */
public class LeaveRequestTriggerHandler implements ITriggerHandler {

    public void beforeInsert(List<SObject> newList) {
        List<Leave_Request__c> leaves = (List<Leave_Request__c>) newList;
        // Balance check first: if balance is insufficient, block before overlap check
        LeaveRequestService.validateBalance(leaves);
        // Overlap detection: sets Status = Rejected (does not block; inserts with audit trail)
        LeaveRequestService.detectAndRejectOverlaps(leaves);
    }

    public void afterInsert(List<SObject> newList, Map<Id, SObject> oldMap) {
        // Enqueue async routing to avoid Mixed DML when submitting to Approval Process
        System.enqueueJob(new LeaveApprovalQueueable((List<Leave_Request__c>) newList));
    }

    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        // When Approval Process finalises and sets Status__c = 'Approved',
        // decrement the employee's balance here to cover both the approval-process
        // path and any manual status changes by admins.
        List<Id> newlyApproved = new List<Id>();
        for (Leave_Request__c lr : (List<Leave_Request__c>) newList) {
            Leave_Request__c oldLr = (Leave_Request__c) oldMap.get(lr.Id);
            if (lr.Status__c == 'Approved' && oldLr.Status__c != 'Approved') {
                newlyApproved.add(lr.Id);
            }
        }
        if (!newlyApproved.isEmpty()) {
            LeaveRequestService.decrementBalance(newlyApproved);
        }
    }

    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void beforeDelete(List<SObject> oldList) {}
    public void afterDelete(List<SObject> oldList, Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newList) {}
}
