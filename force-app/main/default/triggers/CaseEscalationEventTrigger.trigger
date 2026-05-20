/**
 * CaseEscalationEventTrigger
 * Subscribes to Case_Escalation_Event__e platform events.
 *
 * This trigger always executes as the Automated Process user — a system-level
 * internal user — regardless of who published the event. That is the key
 * property that allows the handler to query setup objects (OrgWideEmailAddress)
 * that are blocked for Experience Cloud portal users.
 */
trigger CaseEscalationEventTrigger on Case_Escalation_Event__e (after insert) {
    CaseEscalationEventHandler.handleEvents(Trigger.new);
}
