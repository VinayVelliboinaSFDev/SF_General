/**
 * CaseTriggerHandler
 * Routes Case trigger events to service classes.
 * Owns no business logic — purely a coordinator.
 *
 * Scenario 05 – Case SLA Escalation
 * When a Case's SLA_Due_Date__c is updated to a value in the past,
 * the Case is automatically reassigned to the Case Escalation Queue
 * and its Priority/Status are set to High/Escalated.
 */
public class CaseTriggerHandler implements ITriggerHandler {

    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        CaseSLAEscalationService.escalateOverdueCases(
            (List<Case>) newList,
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
