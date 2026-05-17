/**
 * AttendanceTrigger
 * One trigger per object. All logic lives in AttendanceTriggerHandler.
 */
trigger AttendanceTrigger on Attendance__c (before insert) {
    TriggerDispatcher.run(new AttendanceTriggerHandler());
}
