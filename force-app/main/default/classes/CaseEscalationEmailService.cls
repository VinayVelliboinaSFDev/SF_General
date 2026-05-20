/**
 * CaseEscalationEmailService
 * Detects when a Case transitions to Status=Escalated + Priority=High and
 * publishes a Case_Escalation_Event__e Platform Event.
 *
 * WHY Platform Events instead of Queueable:
 *   A Queueable job runs as the user who enqueued it. When an Experience Cloud
 *   (portal) user triggers the enqueue, the Queueable also runs under that
 *   portal user's license — which still cannot access setup objects such as
 *   OrgWideEmailAddress. 'without sharing' bypasses record-level sharing rules
 *   only; it does NOT override license-based setup object restrictions.
 *
 *   Platform Event subscriber triggers always execute as the Automated Process
 *   user — a system-level internal user with full setup object access. This is
 *   the correct and guaranteed mechanism for bypassing portal user restrictions.
 *
 * Design decisions:
 *
 *  1. Change detection (old.Status != 'Escalated') prevents re-publishing an
 *     event every time an already-escalated Case is saved again.
 *
 *  2. The static Set<Id> `processed` blocks re-entrant trigger fires from
 *     publishing duplicate events within the same transaction (e.g., when
 *     CaseSLAEscalationService's DML re-fires the trigger for the same Case).
 *
 *  3. EventBus.publish() is bulkified — one call publishes the entire list
 *     regardless of how many Cases qualify.
 */
public with sharing class CaseEscalationEmailService {

    @TestVisible
    private static Set<Id> processed = new Set<Id>();

    public static void notifyOnEscalation(
        List<Case> newCases,
        Map<Id, SObject> oldMap
    ) {
        List<Case_Escalation_Event__e> events =
            new List<Case_Escalation_Event__e>();

        for (Case c : newCases) {
            if (processed.contains(c.Id)) {
                continue; // recursion guard
            }
            if (c.Status != 'Escalated' || c.Priority != 'High') {
                continue;
            }
            Case oldCase = (Case) oldMap.get(c.Id);
            if (oldCase.Status == 'Escalated') {
                continue; // already escalated — no new event needed
            }

            processed.add(c.Id);
            events.add(new Case_Escalation_Event__e(
                Case_Id__c     = c.Id,
                Case_Number__c = c.CaseNumber,
                Subject__c     = c.Subject
            ));
        }

        if (!events.isEmpty()) {
            EventBus.publish(events);
        }
    }
}
