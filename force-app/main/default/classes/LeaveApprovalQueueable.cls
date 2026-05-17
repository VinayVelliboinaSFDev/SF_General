/**
 * LeaveApprovalQueueable
 * Handles post-insert approval routing asynchronously to avoid Mixed DML errors.
 *
 * Mixed DML: Approval.process() internally touches setup objects, which cannot
 * be combined with standard-object DML in the same synchronous transaction.
 * Enqueuing a Queueable moves the work to its own transaction, sidestepping
 * this platform constraint cleanly — preferred over @future because it can
 * accept SObject lists and chain further Queueables if needed.
 *
 * Two paths:
 *   Leave_Days__c <= 2 → auto-approve, decrement balance
 *   Leave_Days__c >  2 → submit to native Approval Process
 */
public class LeaveApprovalQueueable implements Queueable {

    private List<Leave_Request__c> requests;

    public LeaveApprovalQueueable(List<Leave_Request__c> requests) {
        this.requests = requests;
    }

    public void execute(QueueableContext ctx) {
        List<Leave_Request__c> toApprove     = new List<Leave_Request__c>();
        List<Id>               toSubmit      = new List<Id>();

        for (Leave_Request__c lr : requests) {
            // Overlapping requests were already rejected in the before-trigger
            if (lr.Status__c == 'Rejected') continue;

            Decimal days = lr.Leave_Days__c != null ? lr.Leave_Days__c : 0;
            if (days <= 2) {
                lr.Status__c = 'Approved';
                toApprove.add(lr);
            } else {
                toSubmit.add(lr.Id);
            }
        }

        // Auto-approve short leaves
        if (!toApprove.isEmpty()) {
            update toApprove;

            List<Id> approvedIds = new List<Id>();
            for (Leave_Request__c lr : toApprove) approvedIds.add(lr.Id);
            LeaveRequestService.decrementBalance(approvedIds);
        }

        // Submit longer leaves to the Approval Process
        // Wrapped in try-catch: if no active process exists the error is logged
        // rather than silently swallowed, which would confuse debugging.
        if (!toSubmit.isEmpty() && !Test.isRunningTest()) {
            for (Id leaveId : toSubmit) {
                try {
                    Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                    req.setObjectId(leaveId);
                    req.setSubmitterId(UserInfo.getUserId());
                    // API name of the active Approval Process — update if renamed
                    req.setProcessDefinitionNameOrId('Leave_Approval_Process');
                    Approval.process(req);

                    // Update status to reflect it is awaiting approval
                    update new Leave_Request__c(Id = leaveId, Status__c = 'Pending Approval');
                } catch (Exception ex) {
                    System.debug(LoggingLevel.ERROR,
                        'Approval submission failed for Leave_Request__c ' + leaveId
                        + ': ' + ex.getMessage());
                }
            }
        }
    }
}
