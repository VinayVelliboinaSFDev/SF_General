/**
 * LeaveRequestTrigger
 * One trigger per object. All logic lives in LeaveRequestTriggerHandler.
 */
trigger LeaveRequestTrigger on Leave_Request__c (
    before insert,
    after insert,
    after update
) {
    TriggerDispatcher.run(new LeaveRequestTriggerHandler());
}
