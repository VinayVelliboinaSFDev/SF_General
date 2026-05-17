/**
 * TestDataFactory
 * Central builder for all test records in this repo. Every scenario's test
 * class calls these methods instead of writing inline SObject construction.
 * This keeps tests readable and ensures consistent field values across scenarios.
 *
 * All methods insert the record and return it with a populated Id unless the
 * method name ends in "Build" — those return an unsaved SObject.
 */
@IsTest
public class TestDataFactory {

    // ─── Salesforce Standard ──────────────────────────────────────────────

    public static Account createAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    /** Returns an unsaved Account — caller inserts. */
    public static Account buildAccount(String name, Decimal annualRevenue) {
        return new Account(Name = name, AnnualRevenue = annualRevenue);
    }

    /** Inserts and returns an Account with AnnualRevenue pre-set. */
    public static Account createAccountWithRevenue(String name, Decimal annualRevenue) {
        Account a = buildAccount(name, annualRevenue);
        insert a;
        return a;
    }

    public static Opportunity createOpportunity(Id accountId, String name, Date closeDate) {
        Opportunity o = new Opportunity(
            AccountId   = accountId,
            Name        = name,
            CloseDate   = closeDate,
            StageName   = 'Prospecting'
        );
        insert o;
        return o;
    }

    /** Returns an unsaved Opportunity in Prospecting stage — caller inserts. */
    public static Opportunity buildOpportunity(Id accountId, String name, Date closeDate) {
        return new Opportunity(
            AccountId = accountId,
            Name      = name,
            CloseDate = closeDate,
            StageName = 'Prospecting'
        );
    }

    public static Product2 createProduct(String name) {
        Product2 p = new Product2(Name = name, IsActive = true);
        insert p;
        return p;
    }

    /**
     * Creates a PricebookEntry in the Standard Pricebook.
     * Tests must call Test.getStandardPricebookId() — that value is passed in.
     */
    public static PricebookEntry createPricebookEntry(Id productId, Decimal unitPrice) {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = productId,
            UnitPrice    = unitPrice,
            IsActive     = true
        );
        insert pbe;
        return pbe;
    }

    public static OpportunityLineItem createLineItem(
        Id opportunityId,
        Id pricebookEntryId,
        Decimal quantity,
        Decimal unitPrice,
        Decimal discount
    ) {
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId    = opportunityId,
            PricebookEntryId = pricebookEntryId,
            Quantity         = quantity,
            UnitPrice        = unitPrice,
            Discount         = discount
        );
        insert oli;
        return oli;
    }

    // ─── Scenario 05 – Case SLA Escalation ───────────────────────────────

    /** Returns an unsaved Case in 'New' status — caller inserts. */
    public static Case buildCase(String subject) {
        return new Case(
            Subject  = subject,
            Status   = 'New',
            Priority = 'Medium',
            Origin   = 'Web'
        );
    }

    /** Inserts and returns a Case in 'New' status with no SLA date set. */
    public static Case createCase(String subject) {
        Case c = buildCase(subject);
        insert c;
        return c;
    }

    // ─── Scenario 02 – Student Attendance ────────────────────────────────

    public static Student__c createStudent(String name) {
        Student__c s = new Student__c(Name = name, Status__c = 'Active');
        insert s;
        return s;
    }

    public static Attendance__c createAttendance(Id studentId, Date attendDate, String status) {
        Attendance__c a = new Attendance__c(
            Student__c = studentId,
            Date__c    = attendDate,
            Status__c  = status
        );
        insert a;
        return a;
    }

    /**
     * Bulk-creates attendance records for a student without inserting them.
     * Caller inserts the list so that trigger context fires once.
     */
    public static List<Attendance__c> buildAttendanceList(
        Id studentId,
        Date startDate,
        Integer totalDays,
        Integer presentDays
    ) {
        List<Attendance__c> records = new List<Attendance__c>();
        for (Integer i = 0; i < totalDays; i++) {
            records.add(new Attendance__c(
                Student__c = studentId,
                Date__c    = startDate.addDays(i),
                Status__c  = (i < presentDays) ? 'Present' : 'Absent'
            ));
        }
        return records;
    }

    // ─── Scenario 03 – Leave Management ──────────────────────────────────

    public static Employee__c createEmployee(String name, Integer leaveBalance) {
        Employee__c e = new Employee__c(
            Name              = name,
            Leave_Balance__c  = leaveBalance
        );
        insert e;
        return e;
    }

    public static Leave_Request__c createLeaveRequest(
        Id employeeId,
        Date startDate,
        Date endDate,
        String leaveType
    ) {
        Leave_Request__c lr = new Leave_Request__c(
            Employee__c  = employeeId,
            Start_Date__c = startDate,
            End_Date__c  = endDate,
            Leave_Type__c = leaveType,
            Status__c    = 'Draft'
        );
        insert lr;
        return lr;
    }

    /** Returns an unsaved Leave_Request__c for use in bulk insert scenarios. */
    public static Leave_Request__c buildLeaveRequest(
        Id employeeId,
        Date startDate,
        Date endDate,
        String leaveType
    ) {
        return new Leave_Request__c(
            Employee__c   = employeeId,
            Start_Date__c = startDate,
            End_Date__c   = endDate,
            Leave_Type__c = leaveType,
            Status__c     = 'Draft'
        );
    }
}
