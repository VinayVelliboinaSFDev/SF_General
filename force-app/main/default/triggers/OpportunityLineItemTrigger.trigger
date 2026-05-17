/**
 * OpportunityLineItemTrigger
 * One trigger per object. All logic lives in the handler and service layers.
 */
trigger OpportunityLineItemTrigger on OpportunityLineItem (
    before insert, before update, before delete,
    after insert,  after update,  after delete,  after undelete
) {
    TriggerDispatcher.run(new OpportunityLineItemTriggerHandler());
}
