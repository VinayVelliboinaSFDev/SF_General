/**
 * AttendanceService
 * Business logic for attendance records.
 * Centralises the duplicate-entry check and the aggregate rate calculation
 * so both the trigger and the batch can share this code without duplication.
 */
public class AttendanceService {

    @TestVisible private static final String MSG_DUPLICATE_ATTENDANCE =
        'Attendance for this student on this date has already been recorded.';

    // ─── Trigger Logic ────────────────────────────────────────────────────

    /**
     * Blocks inserting an Attendance__c when a record already exists for
     * the same Student and Date.
     *
     * Uses a single SOQL query for the entire batch — no query inside a loop.
     *
     * @param newList  Trigger.new (before insert context only)
     */
    public static void validateNoDuplicateEntry(List<Attendance__c> newList) {
        Set<Id>   studentIds = new Set<Id>();
        Set<Date> dates      = new Set<Date>();

        for (Attendance__c a : newList) {
            if (a.Student__c != null && a.Date__c != null) {
                studentIds.add(a.Student__c);
                dates.add(a.Date__c);
            }
        }

        if (studentIds.isEmpty()) return;

        // Build a composite key set from existing records
        Set<String> existingKeys = new Set<String>();
        for (Attendance__c existing : [
            SELECT Student__c, Date__c
            FROM   Attendance__c
            WHERE  Student__c IN :studentIds
              AND  Date__c    IN :dates
        ]) {
            existingKeys.add(compositeKey(existing.Student__c, existing.Date__c));
        }

        // Also check within the current batch for same-day duplicates in a bulk insert
        Set<String> seenInBatch = new Set<String>();

        for (Attendance__c a : newList) {
            String key = compositeKey(a.Student__c, a.Date__c);
            if (existingKeys.contains(key) || seenInBatch.contains(key)) {
                a.addError(MSG_DUPLICATE_ATTENDANCE);
            } else {
                seenInBatch.add(key);
            }
        }
    }

    // ─── Batch Support ────────────────────────────────────────────────────

    /**
     * Calculates the attendance percentage for each student in the given set.
     * Uses aggregate SOQL so only one row is returned per student per status —
     * safe even when a student has years of daily records.
     *
     * @param studentIds  IDs of students in the current batch chunk
     * @return Map<Id, Decimal> studentId → attendance percentage (0–100)
     */
    public static Map<Id, Decimal> calculateRates(Set<Id> studentIds) {
        Map<Id, Integer> presentCount = new Map<Id, Integer>();
        Map<Id, Integer> totalCount   = new Map<Id, Integer>();

        // Prime the maps so students with zero records still get a 0% result
        for (Id sid : studentIds) {
            presentCount.put(sid, 0);
            totalCount.put(sid, 0);
        }

        for (AggregateResult ar : [
            SELECT Student__c sid, Status__c status, COUNT(Id) cnt
            FROM   Attendance__c
            WHERE  Student__c IN :studentIds
            GROUP BY Student__c, Status__c
        ]) {
            Id sid      = (Id)      ar.get('sid');
            String stat = (String)  ar.get('status');
            Integer cnt = (Integer) ar.get('cnt');

            totalCount.put(sid, totalCount.get(sid) + cnt);
            if (stat == 'Present') {
                presentCount.put(sid, presentCount.get(sid) + cnt);
            }
        }

        Map<Id, Decimal> rates = new Map<Id, Decimal>();
        for (Id sid : studentIds) {
            Integer total   = totalCount.get(sid);
            Integer present = presentCount.get(sid);
            rates.put(sid, total == 0 ? 0 : ((Decimal) present / total * 100).setScale(2));
        }
        return rates;
    }

    // ─── Private Helpers ─────────────────────────────────────────────────

    private static String compositeKey(Id studentId, Date d) {
        return String.valueOf(studentId) + '|' + String.valueOf(d);
    }
}
