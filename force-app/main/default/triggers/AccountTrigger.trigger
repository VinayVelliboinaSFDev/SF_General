/**
 * AccountTrigger
 * One trigger per object. All logic lives in AccountTriggerHandler.
 * Subscribes only to the events that have registered handlers.
 */
trigger AccountTrigger on Account (
    before insert,
    before update,
    after insert,
    after update
) {
    TriggerDispatcher.run(new AccountTriggerHandler());
}
