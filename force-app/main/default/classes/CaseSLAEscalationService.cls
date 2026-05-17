/**
 * CaseSLAEscalationService
 * Business logic for Scenario 05 – Case SLA Escalation.
 *
 * Rule: when a Case's SLA_Due_Date__c is updated and the new value is in the
 * past (overdue), the Case is reassigned to the Case Escalation Queue,
 * Priority is set to High, and Status is set to Escalated.
 *
 * Design decisions:
 *
 *  1. Change detection (old vs new SLA_Due_Date__c) ensures the service only
 *     acts on the update event, not on every subsequent save where the date
 *     is still overdue. This prevents redundant DML on steady-state updates.
 *
 *  2. The escalation queue Id is resolved lazily once per transaction
 *     (transactionQueueId). Calling [SELECT Id FROM Group ...] inside a loop
 *     would burn SOQL limits in a bulk context.
 *
 *  3. The static Set<Id> `processed` is the per-transaction recursion guard.
 *     When the DML inside this service fires the CaseTrigger again for the
 *     same Case Ids, those Ids are already in `processed` so the second fire
 *     exits immediately without further DML.
 *     The set is populated BEFORE the DML call to handle re-entrant fires
 *     that can happen mid-update in some automation stacks.
 *
 *  4. Terminal-state check (IsClosed) is evaluated per Case before any DML
 *     to ensure closed Cases are never touched, regardless of their SLA date.
 *
 *  5. Already-in-escalation-queue check (c.OwnerId == transactionQueueId)
 *     is done in the build loop so the SOQL query is issued only once for
 *     the whole batch, not once per Case.
 */
public with sharing class CaseSLAEscalationService {

    /**
     * DeveloperName of the escalation queue used in production.
     * Declared as a mutable @TestVisible static so that unit tests can point
     * to a test-only queue (avoiding DUPLICATE_DEVELOPER_NAME collisions with
     * the metadata-deployed queue that already exists in the org).
     */
    @TestVisible
    private static String escalationQueueDevName = 'Case_Escalation_Queue';

    /**
     * Per-transaction recursion guard.
     * Populated before DML to prevent re-entrant trigger fires from
     * re-processing the same Cases.
     */
    @TestVisible
    private static Set<Id> processed = new Set<Id>();

    /**
     * Cached queue Id for the lifetime of the transaction.
     * Avoids repeated SOQL for the same queue in bulk trigger batches.
     */
    @TestVisible
    private static Id transactionQueueId;

    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Entry point called by CaseTriggerHandler.afterUpdate.
     *
     * @param newCases  Trigger.new cast to List<Case>
     * @param oldMap    Trigger.oldMap (SObject map — cast to Case inside)
     */
    public static void escalateOverdueCases(
        List<Case> newCases,
        Map<Id, SObject> oldMap
    ) {
        // Step 1 — identify candidates: SLA_Due_Date__c changed to an overdue
        //          value, Case is open, and not already processed this transaction.
        Set<Id> candidateIds = new Set<Id>();

        for (Case c : newCases) {
            if (processed.contains(c.Id)) {
                continue; // recursion guard: already handled in this transaction
            }
            if (c.IsClosed) {
                continue; // AC5: closed Cases must never be escalated
            }

            Case oldCase = (Case) oldMap.get(c.Id);

            // Only act when SLA_Due_Date__c actually changed
            if (c.SLA_Due_Date__c == oldCase.SLA_Due_Date__c) {
                continue;
            }

            // AC1: if the new due date is in the future, the SLA was extended — no action
            // AC2: if the new due date is in the past, the Case is overdue — escalate
            if (c.SLA_Due_Date__c != null && c.SLA_Due_Date__c < DateTime.now()) {
                candidateIds.add(c.Id);
            }
        }

        if (candidateIds.isEmpty()) {
            return; // nothing qualifies — exit early before any SOQL
        }

        // Step 2 — lazy-resolve the escalation queue Id once per transaction.
        //          Using DeveloperName (not label) because labels can be renamed.
        if (transactionQueueId == null) {
            List<Group> queues = [
                SELECT Id
                FROM   Group
                WHERE  Type          = 'Queue'
                AND    DeveloperName = :escalationQueueDevName
                LIMIT  1
            ];
            if (queues.isEmpty()) {
                return; // escalation queue missing — degrade gracefully, do not throw
            }
            transactionQueueId = queues[0].Id;
        }

        // Step 3 — mark candidates as processed BEFORE DML to block the
        //          re-entrant trigger fire that update causes.
        processed.addAll(candidateIds);

        // Step 4 — build the DML list, skipping any Case already owned by
        //          the escalation queue (AC3) to avoid duplicate assignments.
        List<Case> toUpdate = new List<Case>();
        for (Case c : newCases) {
            if (!candidateIds.contains(c.Id)) {
                continue;
            }
            if (c.OwnerId == transactionQueueId) {
                continue; // AC3: already in escalation queue — skip
            }

            toUpdate.add(new Case(
                Id          = c.Id,
                OwnerId     = transactionQueueId,
                Priority    = 'High',
                Status      = 'Escalated',
                IsEscalated = true
            ));
        }

        // Step 5 — single bulk DML regardless of how many Cases qualify.
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
