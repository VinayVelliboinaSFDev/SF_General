/**
 * AttendanceWarningService
 * Creates Warning__c records for Defaulter students.
 * Deduplicates by ISO week so running the batch multiple times in one week
 * does not generate multiple warnings for the same student.
 */
public class AttendanceWarningService {

    /**
     * Generates Warning__c records for students whose Status__c is 'Defaulter',
     * skipping any student who already has a warning for the current ISO week.
     *
     * Called from AttendanceStatusBatch.execute() after status updates.
     *
     * @param students  The updated Student__c records from the batch chunk
     */
    public static void generateWeeklyWarnings(List<Student__c> students) {
        // Filter to only defaulters in this chunk
        List<Student__c> defaulters = new List<Student__c>();
        for (Student__c s : students) {
            if (s.Status__c == 'Defaulter') {
                defaulters.add(s);
            }
        }
        if (defaulters.isEmpty()) return;

        String weekKey = currentWeekKey();
        Set<Id> defaulterIds = new Map<Id, Student__c>(defaulters).keySet();

        // Find students already warned this week — avoid duplicates
        Set<Id> alreadyWarned = new Set<Id>();
        for (Warning__c w : [
            SELECT Student__c
            FROM   Warning__c
            WHERE  Student__c IN :defaulterIds
              AND  Week_Key__c = :weekKey
        ]) {
            alreadyWarned.add(w.Student__c);
        }

        List<Warning__c> warnings = new List<Warning__c>();
        for (Student__c s : defaulters) {
            if (!alreadyWarned.contains(s.Id)) {
                warnings.add(new Warning__c(
                    Student__c    = s.Id,
                    Warning_Date__c = Date.today(),
                    Week_Key__c   = weekKey,
                    Reason__c     = 'Attendance below 75% threshold. Current rate: '
                                    + s.Attendance_Percentage__c + '%.'
                ));
            }
        }

        if (!warnings.isEmpty()) {
            insert warnings;
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────

    /**
     * Returns the ISO year-week string for today, e.g. "2026-20".
     * Uses Apex Date arithmetic: week number = days since nearest Monday / 7 + 1.
     * Salesforce does not expose a built-in weekNumber() method, so we derive it
     * from the day of the year and the day of the week.
     */
    @TestVisible
    public static String currentWeekKey() {
        return currentWeekKey(Date.today());
    }

    @TestVisible
    public static String currentWeekKey(Date d) {
        // Salesforce Date.toStartOfWeek() returns the Sunday of the week.
        // ISO week starts on Monday. We adjust by adding 1 day if the day
        // is Sunday (dayOfWeek == 1 in Apex's 1=Sun..7=Sat scheme).
        Date startOfWeek = d.toStartOfWeek(); // Sunday
        // Move to Monday
        Date monday = startOfWeek.addDays(1);
        // If today is Sunday, the Monday that matters is the PREVIOUS Monday
        if (d == startOfWeek) {
            monday = startOfWeek.addDays(-6);
        }

        Integer year    = monday.year();
        // Week number: days from Jan 1 to monday, divided by 7, +1
        Date jan1       = Date.newInstance(year, 1, 1);
        Integer dayOfYear = jan1.daysBetween(monday);
        Integer weekNum = (dayOfYear / 7) + 1;

        return year + '-' + String.valueOf(weekNum).leftPad(2, '0');
    }
}
