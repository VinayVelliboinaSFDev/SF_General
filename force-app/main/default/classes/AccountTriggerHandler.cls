/**
 * AccountTriggerHandler
 * Routes Account trigger events to service classes.
 * Owns no business logic — this class is purely a coordinator.
 *
 * Scenario 04 – High-Value Opportunity Reclassification
 * When an Account's AnnualRevenue crosses $1,000,000 on update,
 * all related open Opportunities are stamped Classification__c = 'High Value'.
 */
public class AccountTriggerHandler implements ITriggerHandler {

    // ── afterUpdate is the only event with registered work ───────────────────

    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        AccountHighValueService.reclassifyOpportunities(
            (List<Account>) newList,
            oldMap
        );
    }

    // ── Unused contexts — empty bodies satisfy the interface ─────────────────

    public void beforeInsert(List<SObject> newList) {}
    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void beforeDelete(List<SObject> oldList) {}
    public void afterInsert(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void afterDelete(List<SObject> oldList, Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newList) {}
}
