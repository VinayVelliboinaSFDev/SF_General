/**
 * CaseTriggerHandler
 * Routes Case trigger events to service classes.
 * Owns no business logic — purely a coordinator.
 *
 * Scenario 05 – Case SLA Escalation
 * When a Case's SLA_Due_Date__c is updated to a value in the past,
 * the Case is automatically reassigned to the Case Escalation Queue
 * and its Priority/Status are set to High/Escalated.
 *
 * Scenario 06 – Experience Cloud Escalation Email
 * When a Case transitions to Status=Escalated + Priority=High (whether set
 * directly by a portal user or by the SLA service), an async email is sent
 * to the internal support team via an org-wide email address.
 * The email logic runs in a Queueable to bypass Experience Cloud users'
 * inability to access setup objects like OrgWideEmailAddress.
 */
public class CaseTriggerHandler implements ITriggerHandler {

    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        CaseSLAEscalationService.escalateOverdueCases(
            (List<Case>) newList,
            oldMap
        );
        CaseEscalationEmailService.notifyOnEscalation(
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
