/**
 * CaseTrigger
 * One trigger per object. All logic lives in CaseTriggerHandler.
 */
trigger CaseTrigger on Case (
    before insert,
    before update,
    after insert,
    after update
) {
    TriggerDispatcher.run(new CaseTriggerHandler());
}
