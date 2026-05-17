/**
 * AttendanceStatusBatchTest
 * Covers:
 *   - Duplicate attendance entry blocked by trigger
 *   - Batch sets Defaulter / Active status correctly
 *   - Batch creates Warning records for Defaulters
 *   - Batch skips duplicate warnings for the same week
 *   - Scheduler wires up without error
 *   - Bulk: 200 students processed correctly
 */
@IsTest
private class AttendanceStatusBatchTest {

    // ─── Trigger Tests ────────────────────────────────────────────────────

    @IsTest
    static void testDuplicateAttendanceBlocked() {
        Student__c s = TestDataFactory.createStudent('Alice Johnson');
        TestDataFactory.createAttendance(s.Id, Date.today(), 'Present');

        Attendance__c duplicate = new Attendance__c(
            Student__c = s.Id,
            Date__c    = Date.today(),
            Status__c  = 'Present'
        );

        Test.startTest();
        try {
            insert duplicate;
            Assert.fail('Expected DmlException for duplicate attendance');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains(AttendanceService.MSG_DUPLICATE_ATTENDANCE),
                'Wrong error: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testDifferentDateAllowed() {
        Student__c s = TestDataFactory.createStudent('Bob Smith');
        TestDataFactory.createAttendance(s.Id, Date.today(), 'Present');

        Attendance__c nextDay = new Attendance__c(
            Student__c = s.Id,
            Date__c    = Date.today().addDays(1),
            Status__c  = 'Present'
        );

        Test.startTest();
        insert nextDay;  // no exception expected
        Test.stopTest();

        Assert.isNotNull(nextDay.Id, 'Attendance on a different date should insert');
    }

    // ─── Batch Tests ──────────────────────────────────────────────────────

    @IsTest
    static void testBatchSetsDefaulterStatus() {
        Student__c s = TestDataFactory.createStudent('Defaulter Dan');

        // 4 present out of 10 = 40% — below 75% threshold
        List<Attendance__c> records = TestDataFactory.buildAttendanceList(
            s.Id, Date.today().addDays(-9), 10, 4
        );
        insert records;

        Test.startTest();
        Database.executeBatch(new AttendanceStatusBatch(), 200);
        Test.stopTest();

        Student__c result = [SELECT Status__c, Attendance_Percentage__c FROM Student__c WHERE Id = :s.Id];
        Assert.areEqual('Defaulter', result.Status__c, 'Should be Defaulter at 40%');
        Assert.areEqual(40.00, result.Attendance_Percentage__c, 'Percentage should be 40%');
    }

    @IsTest
    static void testBatchSetsActiveStatus() {
        Student__c s = TestDataFactory.createStudent('Active Alice');

        // 8 present out of 10 = 80% — above threshold
        List<Attendance__c> records = TestDataFactory.buildAttendanceList(
            s.Id, Date.today().addDays(-9), 10, 8
        );
        insert records;

        Test.startTest();
        Database.executeBatch(new AttendanceStatusBatch(), 200);
        Test.stopTest();

        Student__c result = [SELECT Status__c FROM Student__c WHERE Id = :s.Id];
        Assert.areEqual('Active', result.Status__c, 'Should be Active at 80%');
    }

    @IsTest
    static void testBatchGeneratesWarningForDefaulter() {
        Student__c s = TestDataFactory.createStudent('Warning Will');

        List<Attendance__c> records = TestDataFactory.buildAttendanceList(
            s.Id, Date.today().addDays(-9), 10, 3
        );
        insert records;

        Test.startTest();
        Database.executeBatch(new AttendanceStatusBatch(), 200);
        Test.stopTest();

        List<Warning__c> warnings = [SELECT Id FROM Warning__c WHERE Student__c = :s.Id];
        Assert.areEqual(1, warnings.size(), 'Exactly one Warning should be created');
    }

    @IsTest
    static void testBatchSkipsDuplicateWarningForSameWeek() {
        Student__c s = TestDataFactory.createStudent('No Double Warning');

        List<Attendance__c> records = TestDataFactory.buildAttendanceList(
            s.Id, Date.today().addDays(-9), 10, 3
        );
        insert records;

        // Pre-insert a warning for this week
        insert new Warning__c(
            Student__c     = s.Id,
            Warning_Date__c = Date.today(),
            Week_Key__c    = AttendanceWarningService.currentWeekKey(),
            Reason__c      = 'Pre-existing warning'
        );

        Test.startTest();
        Database.executeBatch(new AttendanceStatusBatch(), 200);
        Test.stopTest();

        List<Warning__c> warnings = [SELECT Id FROM Warning__c WHERE Student__c = :s.Id];
        Assert.areEqual(1, warnings.size(), 'No second warning should be created for same week');
    }

    @IsTest
    static void testSchedulerExecutes() {
        Test.startTest();
        AttendanceScheduler.scheduleWeekly();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'Weekly Attendance Status Batch'
        ];
        Assert.areEqual(1, jobs.size(), 'Scheduler should register one cron job');
    }

    @IsTest
    static void testBatchBulk200Students() {
        List<Student__c> students = new List<Student__c>();
        for (Integer i = 0; i < 200; i++) {
            students.add(new Student__c(Name = 'Bulk Student ' + i, Status__c = 'Active'));
        }
        insert students;

        // Give each student 10 attendance records: 6 present (60% → Defaulter)
        List<Attendance__c> allAttendance = new List<Attendance__c>();
        for (Student__c s : students) {
            allAttendance.addAll(
                TestDataFactory.buildAttendanceList(s.Id, Date.today().addDays(-9), 10, 6)
            );
        }
        insert allAttendance;

        Test.startTest();
        Database.executeBatch(new AttendanceStatusBatch(), 200);
        Test.stopTest();

        Integer defaulterCount = [
            SELECT COUNT() FROM Student__c
            WHERE Status__c = 'Defaulter' AND Id IN :students
        ];
        Assert.areEqual(200, defaulterCount, 'All 200 students should be Defaulters at 60%');
    }
}
