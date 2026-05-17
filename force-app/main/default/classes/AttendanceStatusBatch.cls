/**
 * AttendanceStatusBatch
 * Processes all Student__c records in chunks, recalculates attendance
 * percentages via aggregate SOQL, updates Status__c, and generates
 * weekly Warning__c records for Defaulter students.
 *
 * Invocation (Anonymous Apex or AttendanceScheduler):
 *   Database.executeBatch(new AttendanceStatusBatch(), 200);
 */
global class AttendanceStatusBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Stateful counters for the finish() log
    global Integer totalProcessed = 0;
    global Integer defaulterCount = 0;

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Status__c, Attendance_Percentage__c FROM Student__c'
        );
    }

    global void execute(Database.BatchableContext bc, List<Student__c> scope) {
        Set<Id> studentIds = new Map<Id, Student__c>(scope).keySet();

        // One aggregate SOQL for the entire chunk — no per-row queries
        Map<Id, Decimal> rates = AttendanceService.calculateRates(studentIds);

        List<Student__c> toUpdate = new List<Student__c>();
        for (Student__c s : scope) {
            Decimal rate = rates.containsKey(s.Id) ? rates.get(s.Id) : 0;
            String  newStatus = (rate < 75) ? 'Defaulter' : 'Active';

            // Only mark for DML if something actually changed — reduces lock contention
            if (s.Status__c != newStatus || s.Attendance_Percentage__c != rate) {
                s.Status__c               = newStatus;
                s.Attendance_Percentage__c = rate;
                toUpdate.add(s);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        // Generate warnings for defaulters in this chunk (dedup logic inside)
        AttendanceWarningService.generateWeeklyWarnings(toUpdate.isEmpty() ? scope : toUpdate);

        totalProcessed += scope.size();
        for (Student__c s : toUpdate) {
            if (s.Status__c == 'Defaulter') defaulterCount++;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'AttendanceStatusBatch complete. Processed: ' + totalProcessed
            + ' | Defaulters: ' + defaulterCount);
    }
}
