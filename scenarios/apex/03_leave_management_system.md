# Scenario 03 — Leave Management System

**Difficulty:** Advanced  
**Category:** Apex / Trigger Framework / Approval Process / Business Rules Automation

---

## Business Context

A professional services firm tracks employee leave through a custom Salesforce app. HR and payroll teams rely on accurate leave data for compliance reporting. The system must enforce:

- Employees cannot take more leave than they have in their balance — prevents negative balances that break payroll integrations downstream.
- Overlapping leaves for the same employee cause scheduling chaos and must be auto-rejected before they enter an approval queue.
- Short leaves (≤ 2 days) are low-risk and should auto-approve to reduce manager workload.
- Leaves over 2 days require manager review through a formal Approval Process.

This scenario showcases real-world HR automation, date arithmetic in Apex, Approval Process integration via `Process.SubmitRequest`, and Queueable Apex for async approval actions.

---

## Requirements

1. **Balance Check** — When a `Leave_Request__c` is submitted, verify the requested number of days does not exceed `Employee__c.Leave_Balance__c`. Block the save if it does.
2. **Overlap Detection** — If the employee already has an approved or pending leave that overlaps the requested date range, auto-reject the new request (set `Status__c = 'Rejected'`, populate `Rejection_Reason__c`).
3. **Auto-Approve Short Leaves** — If `Leave_Days__c <= 2` and no overlap, programmatically approve the record and decrement `Employee__c.Leave_Balance__c`.
4. **Submit Longer Leaves for Approval** — If `Leave_Days__c > 2` and no overlap, submit the record into the native Salesforce Approval Process. Decrement the balance only after final approval (via Approval Process field update or Process Builder).
5. **Bulk-safe** — All trigger logic must handle batches of 200 requests.

---

## Acceptance Criteria

| # | Given | When | Then |
|---|-------|------|------|
| 1 | Employee has 5 days balance; request is for 6 days | Insert | Save is blocked: *"Insufficient leave balance. Available: 5 days."* |
| 2 | Employee has an approved leave 2026-06-01 to 2026-06-05; new request is 2026-06-03 to 2026-06-07 | Insert | New request `Status__c = 'Rejected'`; `Rejection_Reason__c` = *"Overlaps with existing leave from 01/06/2026 to 05/06/2026."* |
| 3 | Leave_Days__c = 2; no overlap; sufficient balance | Insert | `Status__c = 'Approved'`; `Employee__c.Leave_Balance__c` decremented by 2 |
| 4 | Leave_Days__c = 5; no overlap; sufficient balance | Insert | Record submitted to Approval Process; `Status__c = 'Pending Approval'` |
| 5 | Manager approves the 5-day leave via Approval Process | Approval final approval step | `Employee__c.Leave_Balance__c` decremented by 5 (via Approval Process field update or trigger on status change) |
| 6 | 50 leave requests inserted via Data Loader | — | All validations apply; auto-approvals and submissions process without errors |

---

## Pre-Deployment / Setup Steps

1. Create all custom objects and fields (see Artifacts).
2. Deploy Apex classes and trigger.
3. Create the Approval Process for `Leave_Request__c` (see Implementation Details).
4. Activate the Approval Process **before** testing — `Process.SubmitRequest` will throw an exception if no active process exists for the object.
5. Set `Employee__c.Leave_Balance__c` to a starting value (e.g., 20) for test employees.

---

## Implementation Details / Design

### Object Model

```
Employee__c
    ├── Leave_Balance__c (Number, 4,0 — days remaining)
    └── Manager__c (Lookup → User — used by Approval Process)

Leave_Request__c
    ├── Employee__c (Master-Detail → Employee__c)
    ├── Start_Date__c (Date)
    ├── End_Date__c (Date)
    ├── Leave_Days__c (Formula Number: End_Date__c - Start_Date__c + 1)
    ├── Status__c (Picklist: Draft | Pending Approval | Approved | Rejected)
    ├── Rejection_Reason__c (Long Text Area)
    └── Leave_Type__c (Picklist: Annual | Sick | Unpaid | Maternity)
```

**Why Master-Detail?**  
Cascade delete keeps leave history clean when an employee record is removed during testing. In production you would evaluate converting to Lookup with a retention policy.

### Trigger Architecture

```
LeaveRequestTrigger (before insert, after insert)
    └── LeaveRequestTriggerHandler
            ├── before insert → LeaveRequestService.validateAndProcess()
            └── after insert  → LeaveApprovalQueueable (enqueued for auto-approve/submit)
```

**Why split before/after?**

- **Before insert:** Run balance check and overlap detection. Use `addError()` to block invalid records before they are committed. Also set `Status__c = 'Rejected'` for overlapping records here — they still insert, just with the rejected status (design choice: record the rejection history rather than silently blocking it).
- **After insert:** The record now has an `Id`, which is required to submit to an Approval Process (`Process.SubmitRequest` needs a record Id). Enqueue `LeaveApprovalQueueable` to avoid mixed DML (inserting `ProcessInstanceWorkitem` from a trigger context).

**Mixed DML note:** Calling `Approval.process()` directly in a trigger context raises `MIXED_DML_OPERATION` because Approval submissions involve setup objects. Enqueuing a `Queueable` sidesteps this.

### LeaveRequestService — Before Insert Logic

```
validateBalance(Leave_Request__c lr, Map<Id, Employee__c> employeeMap):
    Employee__c emp = employeeMap.get(lr.Employee__c);
    if lr.Leave_Days__c > emp.Leave_Balance__c:
        lr.addError('Insufficient leave balance. Available: ' + emp.Leave_Balance__c + ' days.')

detectOverlap(List<Leave_Request__c> newList, Map<Id, Employee__c> employeeMap):
    1. Collect employee IDs.
    2. Query existing Leave_Request__c:
       WHERE Employee__c IN :empIds
         AND Status__c IN ('Approved', 'Pending Approval')
         AND Start_Date__c <= :maxEndDate   // optimization: coarse pre-filter
         AND End_Date__c   >= :minStartDate
    3. Build Map<Id, List<Leave_Request__c>> empId → existing leaves.
    4. For each incoming request:
       For each existing leave for same employee:
           if NOT (lr.End_Date__c < existing.Start_Date__c
                   OR lr.Start_Date__c > existing.End_Date__c):
               // Ranges overlap
               lr.Status__c = 'Rejected';
               lr.Rejection_Reason__c = 'Overlaps with existing leave from '
                   + existing.Start_Date__c.format() + ' to ' + existing.End_Date__c.format();
```

**Overlap formula explained:** Two date ranges [A_start, A_end] and [B_start, B_end] do NOT overlap only if `A_end < B_start` or `A_start > B_end`. The inverse of that is overlap. This is a classic interval intersection check — an excellent interview whiteboard question.

### LeaveApprovalQueueable — After Insert Logic

```apex
public class LeaveApprovalQueueable implements Queueable {
    private List<Leave_Request__c> requests;

    public LeaveApprovalQueueable(List<Leave_Request__c> requests) {
        this.requests = requests;
    }

    public void execute(QueueableContext ctx) {
        List<Leave_Request__c> toUpdate = new List<Leave_Request__c>();
        List<Id> toSubmit = new List<Id>();
        List<Id> autoApproveIds = new List<Id>();

        for (Leave_Request__c lr : requests) {
            if (lr.Status__c == 'Rejected') continue; // already handled

            if (lr.Leave_Days__c <= 2) {
                // Auto-approve path
                lr.Status__c = 'Approved';
                autoApproveIds.add(lr.Id);
                toUpdate.add(lr);
            } else {
                // Submit to Approval Process
                toSubmit.add(lr.Id);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            // Decrement balance for auto-approved leaves
            LeaveRequestService.decrementBalance(autoApproveIds);
        }

        for (Id leaveId : toSubmit) {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(leaveId);
            req.setSubmitterId(UserInfo.getUserId());
            req.setProcessDefinitionNameOrId('Leave_Approval_Process'); // active process API name
            Approval.process(req);
        }
    }
}
```

### Approval Process Configuration

| Setting | Value |
|---------|-------|
| Process Name | Leave Approval Process |
| API Name | `Leave_Approval_Process` |
| Object | `Leave_Request__c` |
| Entry Criteria | `Leave_Days__c > 2` AND `Status__c = 'Draft'` |
| Approver | `Employee__c.Manager__c` |
| Approval Step Action | Email alert to manager |
| Final Approval Action | Field Update: `Status__c = 'Approved'`; Field Update: decrement `Employee__c.Leave_Balance__c` (use Cross-Object field update or trigger on status change — see note below) |
| Final Rejection Action | Field Update: `Status__c = 'Rejected'` |

**Balance decrement on final approval:** Approval Process field updates cannot perform math on related object fields directly. Options:
- **Option A (simpler):** Trigger on `Leave_Request__c` that fires on `Status__c` changing to `'Approved'` and decrements `Employee__c.Leave_Balance__c` — covers both auto-approve and process approval in one place.
- **Option B:** Use a Flow triggered on `Leave_Request__c.Status__c` change to update the parent.

For the portfolio, implement Option A (trigger-based) for a clean all-Apex story, and document Option B as the low-code alternative.

### Trade-offs / Interview Talking Points

| Decision | Rationale |
|----------|-----------|
| Reject overlaps (insert with Rejected status) vs. block with `addError` | Blocking loses the audit trail. Inserting with `Rejected` status lets HR see the attempt, the reason, and the dates — critical for compliance. |
| Queueable for approval submission | Avoids Mixed DML error; Queueable is the preferred async pattern over `@future` when you need to pass SObject lists |
| Leave_Days__c as formula vs. Apex calculation | Formula runs declaratively; Apex service reads `lr.Leave_Days__c` directly, keeping logic thin |
| Approval Process for > 2 days vs. custom approval flow in Apex | Native Approval Process gives managers a UI, email alerts, and a standard audit trail. Custom Apex would re-invent all of that. Use the platform. |

---

## Salesforce Artifacts

| Artifact | API Name / Value | Notes |
|----------|-----------------|-------|
| Custom Object | `Employee__c` | Label: Employee |
| Field | `Employee__c.Leave_Balance__c` | Number, 4,0 |
| Field | `Employee__c.Manager__c` | Lookup → User |
| Custom Object | `Leave_Request__c` | Label: Leave Request; Master-Detail to Employee__c |
| Field | `Leave_Request__c.Start_Date__c` | Date |
| Field | `Leave_Request__c.End_Date__c` | Date |
| Field | `Leave_Request__c.Leave_Days__c` | Formula Number: `End_Date__c - Start_Date__c + 1` |
| Field | `Leave_Request__c.Status__c` | Picklist: Draft, Pending Approval, Approved, Rejected |
| Field | `Leave_Request__c.Rejection_Reason__c` | Long Text Area (500) |
| Field | `Leave_Request__c.Leave_Type__c` | Picklist: Annual, Sick, Unpaid, Maternity |
| Approval Process | `Leave_Approval_Process` | Entry: Leave_Days__c > 2; Approver: Manager |
| Apex Trigger | `LeaveRequestTrigger` | before insert, after insert |
| Apex Class | `LeaveRequestTriggerHandler` | Handler |
| Apex Class | `LeaveRequestService` | Validation, overlap detection, balance decrement |
| Apex Class | `LeaveApprovalQueueable` | Async auto-approve + approval submission |
| Apex Class | `ITriggerHandler` | Shared interface (from Scenario 01) |
| Apex Class | `TriggerDispatcher` | Shared framework (from Scenario 01) |
| Apex Test | `LeaveRequestTriggerTest` | All business rule tests |
| Apex Test | `LeaveApprovalQueueableTest` | Async approval path tests |
| Apex Class | `TestDataFactory` | Add `createEmployee()`, `createLeaveRequest()` |

---

## Testing Strategy

### TestDataFactory Extensions
```apex
Employee__c emp = TestDataFactory.createEmployee('John Smith', 20);
Leave_Request__c lr = TestDataFactory.createLeaveRequest(
    emp.Id, Date.today(), Date.today().addDays(1), 'Annual'
);
```

### Test Scenarios

| Test Method | What it proves |
|-------------|---------------|
| `testInsufficientBalanceBlocked` | Request days > balance → `addError` fires |
| `testOverlappingLeaveAutoRejected` | Overlapping date range → `Status__c = 'Rejected'` + reason populated |
| `testNonOverlappingLeaveAllowed` | Adjacent date ranges → no rejection |
| `testShortLeaveAutoApproved` | `Leave_Days__c <= 2` → `Status__c = 'Approved'`; balance decremented |
| `testLongLeaveSubmittedToApproval` | `Leave_Days__c > 2` → record enters approval queue |
| `testBalanceDecrementedAfterApproval` | Simulating status change to `Approved` → balance decremented |
| `testBulk50Requests` | 50 requests across 5 employees; all rules apply |
| `testQueueableWithMixedScenarios` | Mix of short/long/overlapping in one batch |

### Mocking Approval Process in Tests
```apex
// Approval.process() cannot run in test context without an active process.
// Use Test.setMock() with a custom interface if needed, or mark the
// Queueable's submit logic conditional on Test.isRunningTest().
// In tests, verify Status__c changes without actually submitting.
```

---

## README Highlights / GitHub Showcase

**What to call out:**
- The interval overlap algorithm (classic CS concept applied in Salesforce).
- Mixed DML avoidance pattern using Queueable.
- Option A vs Option B balance decrement trade-off — shows architectural thinking.
- Native Approval Process integration: using the platform, not re-inventing it.

**Diagram (Mermaid):**
```
flowchart TD
    Insert[Leave_Request__c Insert] --> BT[Before Trigger]
    BT --> BC[Balance Check]
    BC -->|insufficient| ERR[addError - blocked]
    BT --> OV[Overlap Detection]
    OV -->|overlaps| REJ[Status = Rejected]
    OV -->|no overlap| OK[Allow Insert]

    OK --> AT[After Trigger]
    AT --> Q[LeaveApprovalQueueable enqueued]
    Q -->|Leave_Days <= 2| AA[Auto-Approve + Decrement Balance]
    Q -->|Leave_Days > 2| AP[Submit to Approval Process]
    AP -->|Manager Approves| FIN[Status = Approved + Decrement Balance]
    AP -->|Manager Rejects| FINR[Status = Rejected]
```
