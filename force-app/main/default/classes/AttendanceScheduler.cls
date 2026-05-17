/**
 * AttendanceScheduler
 * Thin wrapper that fires AttendanceStatusBatch every Monday at 8 AM.
 *
 * Register once from Anonymous Apex:
 *   AttendanceScheduler.scheduleWeekly();
 *
 * Or via Setup → Scheduled Jobs with cron: 0 0 8 ? * MON
 */
global class AttendanceScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new AttendanceStatusBatch(), 200);
    }

    /** Convenience method — run once from Anonymous Apex to register the job. */
    public static void scheduleWeekly() {
        String cron = '0 0 8 ? * MON'; // Every Monday at 08:00 AM org local time
        System.schedule('Weekly Attendance Status Batch', cron, new AttendanceScheduler());
    }
}
