/**
 * AttendanceTriggerHandler
 * Routes Attendance__c trigger events to service methods.
 */
public class AttendanceTriggerHandler implements ITriggerHandler {

    public void beforeInsert(List<SObject> newList) {
        AttendanceService.validateNoDuplicateEntry((List<Attendance__c>) newList);
    }

    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void beforeDelete(List<SObject> oldList) {}
    public void afterInsert(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void afterDelete(List<SObject> oldList, Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newList) {}
}
