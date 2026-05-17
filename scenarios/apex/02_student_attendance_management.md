# Scenario 02 — Student Attendance Management

**Difficulty:** Intermediate → Advanced  
**Category:** Apex / Batch Apex / Scheduled Apex / Aggregate SOQL

---

## Business Context

An EdTech organization uses Salesforce to manage student records for an online learning platform. Regulatory accreditation requires that students maintain at least 75% attendance across all sessions. The compliance team needs:

- Automatic status updates on student records when attendance drops below the threshold.
- Weekly warning records generated for at-risk students so advisors can follow up.
- A hard block preventing data-entry operators from logging the same student's attendance twice on the same date.

This scenario covers a common non-CRM Salesforce use case (education/non-profit sector) and showcases Batch + Scheduled Apex, Aggregate SOQL, and parent-child data processing — all frequent interview topics.

---

## Requirements

1. **Defaulter Status** — If a student's attendance percentage (attended sessions / total sessions × 100) drops below 75%, set `Status__c = 'Defaulter'` on `Student__c`. If it recovers to ≥ 75%, set `Status__c = 'Active'`.
2. **Weekly Warning Records** — Every Monday at 8 AM, generate one `Warning__c` record per student who is currently in `Defaulter` status. Do not create duplicate warnings for the same week.
3. **Duplicate Attendance Prevention** — Block inserting an `Attendance__c` record if a record already exists for the same `Student__c` and the same `Date__c`.
4. **Bulk-safe** — Batch must process orgs with up to 50,000 student records without hitting heap or CPU limits.

---

## Acceptance Criteria

| # | Given | When | Then |
|---|-------|------|------|
| 1 | Student has 6 attended / 10 total sessions (60%) | Batch runs | `Student__c.Status__c` = `'Defaulter'` |
| 2 | Student has 8 attended / 10 total sessions (80%) | Batch runs | `Student__c.Status__c` = `'Active'` |
| 3 | A `Warning__c` already exists for student in current ISO week | Monday batch runs | No second `Warning__c` is created |
| 4 | Operator inserts `Attendance__c` for Student A on 2026-05-17 | A record already exists for that student on that date | Save is blocked: *"Attendance for this student on this date has already been recorded."* |
| 5 | Batch processes 50,000 students in chunks of 200 | — | Completes without hitting governor limits; each chunk is a self-contained transaction |

---

## Pre-Deployment / Setup Steps

1. Create custom objects and fields listed in the Artifacts section before deploying Apex.
2. After deploying, run `AttendanceScheduler.scheduleWeekly()` from Anonymous Apex once to register the scheduled job (or use Setup → Scheduled Jobs).
3. Seed at least 5 `Student__c` records with linked `Attendance__c` records to validate batch manually.

---

## Implementation Details / Design

### Object Model

```
Student__c
    ├── Status__c (Picklist: Active | Defaulter | Suspended)
    ├── Attendance_Percentage__c (Formula or populated by batch)
    └── Total_Sessions__c (Number — total sessions offered; maintained by admin or a separate process)

Attendance__c (child of Student__c — Master-Detail)
    ├── Student__c (Master-Detail → Student__c)
    ├── Date__c (Date)
    ├── Status__c (Picklist: Present | Absent)
    └── Week_Key__c (Formula Text: TEXT(YEAR(Date__c)) & '-' & TEXT(WEEKNUMBER(Date__c)))

Warning__c (child of Student__c — Master-Detail)
    ├── Student__c (Master-Detail → Student__c)
    ├── Warning_Date__c (Date)
    ├── Week_Key__c (Text 20 — e.g., "2026-20")
    └── Reason__c (Long Text)
```

**Why Master-Detail for Attendance → Student?**  
Roll-up summary fields become available if needed, and cascade delete keeps data clean when test students are removed. Lookup would require manual cleanup logic.

### Trigger: Duplicate Attendance Prevention

```
AttendanceTrigger (before insert)
    └── AttendanceTriggerHandler
            └── AttendanceService.validateNoDuplicateEntry()
```

```
validateNoDuplicateEntry(List<Attendance__c> newList):
    1. Build Set<Id> studentIds, Set<Date> dates from newList.
    2. Query: SELECT Student__c, Date__c FROM Attendance__c
              WHERE Student__c IN :studentIds AND Date__c IN :dates
    3. Build Set<String> existingKeys = { studentId + '|' + date }
    4. For each incoming record: if key exists → addError(MSG_DUPLICATE)
```

### Batch: AttendanceStatusBatch

```apex
// Processes all Student__c records in chunks of 200
global class AttendanceStatusBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM Student__c');
    }

    global void execute(Database.BatchableContext bc, List<Student__c> scope) {
        // 1. Collect student IDs in this chunk
        Set<Id> studentIds = new Map<Id, Student__c>(scope).keySet();

        // 2. Aggregate attendance: one query for the entire chunk
        // AggregateResult gives us attended and total counts per student
        Map<Id, Decimal> attendanceRateById = AttendanceService.calculateRates(studentIds);

        // 3. Determine status and collect students to update
        List<Student__c> toUpdate = new List<Student__c>();
        for (Student__c s : scope) {
            Decimal rate = attendanceRateById.get(s.Id) ?? 0;
            s.Status__c = (rate < 75) ? 'Defaulter' : 'Active';
            s.Attendance_Percentage__c = rate;
            toUpdate.add(s);
        }

        // 4. Single DML per chunk
        update toUpdate;

        // 5. Generate warnings for defaulters in this chunk
        AttendanceWarningService.generateWeeklyWarnings(toUpdate);
    }

    global void finish(Database.BatchableContext bc) {
        // Log completion or send admin email
    }
}
```

### AttendanceService.calculateRates()

```
SELECT Student__c, Status__c, COUNT(Id) cnt
FROM Attendance__c
WHERE Student__c IN :studentIds
GROUP BY Student__c, Status__c

→ Build Map<Id, Integer> presentCount, totalCount per student
→ Return Map<Id, Decimal> rate = (present / total) * 100
```

**Why Aggregate SOQL instead of querying all Attendance records?**  
A student with 3 years of daily attendance has ~750 records. Querying raw records across 200 students = up to 150,000 rows — easily hitting the 50,000 SOQL row limit. Aggregating pushes the math to the database and returns one row per student per status.

### AttendanceWarningService.generateWeeklyWarnings()

```
1. Filter defaulter students from the batch chunk.
2. Calculate current ISO week key: YYYY-W## (use Date arithmetic).
3. Query existing Warning__c for this week: WHERE Student__c IN :ids AND Week_Key__c = :weekKey
4. Build Set<Id> alreadyWarned.
5. Insert Warning__c only for students not in alreadyWarned.
```

### Scheduler: AttendanceScheduler

```apex
global class AttendanceScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new AttendanceStatusBatch(), 200);
    }

    // Helper — call once from Anonymous Apex
    public static void scheduleWeekly() {
        String cron = '0 0 8 ? * MON'; // Every Monday 8:00 AM
        System.schedule('Weekly Attendance Batch', cron, new AttendanceScheduler());
    }
}
```

### Trade-offs / Interview Talking Points

| Decision | Rationale |
|----------|-----------|
| Batch size = 200 | Default SOQL limit per transaction; 200 students × aggregate query = well within limits |
| Status updated in batch, not trigger | Attendance % requires aggregate across all records — can't do this accurately in a row-level before trigger |
| Week deduplication via `Week_Key__c` text field | Avoids date-range queries; formula field makes it derivable without extra Apex |
| `Database.executeBatch` from Scheduler | Decouples schedule from batch implementation; scheduler is a thin wrapper |

---

## Salesforce Artifacts

| Artifact | API Name / Value | Notes |
|----------|-----------------|-------|
| Custom Object | `Student__c` | Label: Student |
| Field | `Student__c.Status__c` | Picklist: Active, Defaulter, Suspended |
| Field | `Student__c.Attendance_Percentage__c` | Percent, 5,2 |
| Field | `Student__c.Total_Sessions__c` | Number, 4,0 |
| Custom Object | `Attendance__c` | Label: Attendance; Master-Detail to Student__c |
| Field | `Attendance__c.Date__c` | Date |
| Field | `Attendance__c.Status__c` | Picklist: Present, Absent |
| Field | `Attendance__c.Week_Key__c` | Formula Text: `TEXT(YEAR(Date__c)) & "-" & TEXT(WEEKNUMBER(Date__c))` |
| Custom Object | `Warning__c` | Label: Warning; Master-Detail to Student__c |
| Field | `Warning__c.Warning_Date__c` | Date |
| Field | `Warning__c.Week_Key__c` | Text(20) |
| Field | `Warning__c.Reason__c` | Long Text Area |
| Apex Trigger | `AttendanceTrigger` | On `Attendance__c`, before insert |
| Apex Class | `AttendanceTriggerHandler` | Handler |
| Apex Class | `AttendanceService` | Validation + aggregate rate calculation |
| Apex Class | `AttendanceWarningService` | Warning dedup and creation |
| Apex Class | `AttendanceStatusBatch` | `Database.Batchable<SObject>` |
| Apex Class | `AttendanceScheduler` | `Schedulable`; includes `scheduleWeekly()` helper |
| Apex Test | `AttendanceTriggerTest` | Duplicate prevention |
| Apex Test | `AttendanceStatusBatchTest` | Batch + rollup + warning tests |
| Apex Class | `TestDataFactory` | Shared — add `createStudent()`, `createAttendance()` methods |

---

## Testing Strategy

### TestDataFactory Extensions
```apex
Student__c s = TestDataFactory.createStudent('Alice Johnson');
Attendance__c a = TestDataFactory.createAttendance(s.Id, Date.today(), 'Present');
```

### Test Scenarios

| Test Method | What it proves |
|-------------|---------------|
| `testDuplicateAttendanceBlocked` | Same student + date → `addError` fires |
| `testDifferentDateAllowed` | Same student, different date → inserts cleanly |
| `testBatchSetsDefaulterStatus` | < 75% attendance → `Status__c = 'Defaulter'` |
| `testBatchSetsActiveStatus` | ≥ 75% attendance → `Status__c = 'Active'` |
| `testBatchGeneratesWarning` | Defaulter with no existing warning this week → `Warning__c` created |
| `testBatchSkipsDuplicateWarning` | Defaulter already has warning this week → no second `Warning__c` |
| `testBatchBulk200Students` | 200 students; verify all statuses and warnings correct |
| `testSchedulerExecutes` | `Test.startTest()` → `Database.executeBatch` is invoked via scheduler |

---

## README Highlights / GitHub Showcase

**What to call out:**
- Aggregate SOQL pattern avoiding row-limit issues at scale.
- Batch + Scheduler pattern with a clean one-liner `scheduleWeekly()`.
- ISO week key approach for deduplication without complex date-range queries.

**Diagram (Mermaid):**
```
flowchart TD
    Sched[AttendanceScheduler - Monday 8AM] --> Batch[AttendanceStatusBatch]
    Batch -->|execute chunk| AggSOQL[Aggregate SOQL - rates per student]
    AggSOQL --> StatusUpdate[Update Student Status and Percentage]
    StatusUpdate --> WarnSvc[AttendanceWarningService]
    WarnSvc -->|check existing warnings| WarnInsert[Insert Warning__c if not already this week]

    Trigger[AttendanceTrigger - before insert] --> Handler[AttendanceTriggerHandler]
    Handler --> DupCheck[AttendanceService.validateNoDuplicateEntry]
    DupCheck -->|duplicate found| Error[addError on record]
```
