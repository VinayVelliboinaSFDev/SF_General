/**
 * AccountHighValueService
 * Business logic for Scenario 04 – High-Value Opportunity Reclassification.
 *
 * Rule: when an Account's AnnualRevenue transitions from < $1 M to >= $1 M,
 * every related open Opportunity is stamped Classification__c = 'High Value'.
 *
 * Design decisions worth discussing in interviews:
 *  1. Threshold comparison uses old vs new revenue so we only act on the
 *     crossing event, not on every save where revenue is already >= $1 M.
 *     This avoids unnecessary DML on steady-state updates.
 *
 *  2. Terminal-stage filtering is done in SOQL (NOT IN) rather than Apex
 *     to keep the result set small and respect the 50,000-row query limit.
 *
 *  3. The static Set<Id> `processed` acts as a per-transaction recursion
 *     guard. If automation (e.g., a Process Builder or Flow) re-saves the
 *     same Account in the same transaction, we skip accounts we already
 *     handled and avoid duplicate Opportunity updates.
 *
 *  4. All DML is collected into a single update call (bulkified) to stay
 *     well within the 150 DML-statement governor limit even when hundreds
 *     of Accounts cross the threshold in one batch.
 */
public with sharing class AccountHighValueService {

    /** Revenue threshold that triggers reclassification. */
    @TestVisible
    private static final Decimal REVENUE_THRESHOLD = 1000000;

    /**
     * Stages where an Opportunity is considered terminal.
     * These Opps must never be reclassified regardless of Account revenue.
     */
    @TestVisible
    private static final Set<String> TERMINAL_STAGES = new Set<String>{
        'Closed Won',
        'Closed Lost',
        'Cancelled'
    };

    /**
     * Per-transaction guard.
     * Tracks Account Ids already processed in this execution context so that
     * re-entrant trigger fires (e.g., from automation touching the same
     * Account record) do not re-update the same Opportunities.
     */
    @TestVisible
    private static Set<Id> processed = new Set<Id>();

    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Entry point called by AccountTriggerHandler.afterUpdate.
     *
     * @param newAccounts  Trigger.new cast to List<Account>
     * @param oldMap       Trigger.oldMap (SObject map — cast to Account inside)
     */
    public static void reclassifyOpportunities(
        List<Account> newAccounts,
        Map<Id, SObject> oldMap
    ) {
        // Step 1 — identify Accounts that just crossed the threshold
        //          and have not already been processed this transaction.
        Set<Id> crossingIds = new Set<Id>();

        for (Account acc : newAccounts) {
            if (processed.contains(acc.Id)) {
                continue; // already handled in this transaction — skip
            }

            Account oldAcc = (Account) oldMap.get(acc.Id);

            Boolean wasBelow = (oldAcc.AnnualRevenue == null)
                                || (oldAcc.AnnualRevenue < REVENUE_THRESHOLD);
            Boolean isAtOrAbove = (acc.AnnualRevenue != null)
                                   && (acc.AnnualRevenue >= REVENUE_THRESHOLD);

            if (wasBelow && isAtOrAbove) {
                crossingIds.add(acc.Id);
            }
        }

        if (crossingIds.isEmpty()) {
            return; // nothing to do — exit early to avoid a pointless SOQL call
        }

        // Mark these accounts as processed BEFORE the DML so that any
        // re-entrant trigger fire in the same transaction is blocked.
        processed.addAll(crossingIds);

        // Step 2 — query related open Opportunities in one SOQL call.
        //          Filtering terminal stages in SOQL keeps the heap small.
        List<Opportunity> oppsToUpdate = [
            SELECT Id, Classification__c
            FROM   Opportunity
            WHERE  AccountId IN :crossingIds
            AND    StageName NOT IN :TERMINAL_STAGES
            AND    IsClosed = FALSE
        ];

        if (oppsToUpdate.isEmpty()) {
            return;
        }

        // Step 3 — stamp every qualifying Opportunity in memory first,
        //          then issue a single bulk DML call.
        for (Opportunity opp : oppsToUpdate) {
            opp.Classification__c = 'High Value';
        }

        // update — one DML call regardless of how many Opps are in the list.
        update oppsToUpdate;
    }
}
