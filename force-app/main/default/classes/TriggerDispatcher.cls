/**
 * TriggerDispatcher
 * Single entry point for all triggers. Reads the current trigger context
 * and routes to the correct handler method. Triggers pass `this` handler
 * instance; no Custom Metadata lookup needed for this portfolio scope.
 *
 * Usage in a trigger:
 *   TriggerDispatcher.run(new MyObjectTriggerHandler());
 */
public class TriggerDispatcher {

    public static void run(ITriggerHandler handler) {
        if (Trigger.isBefore) {
            if (Trigger.isInsert) handler.beforeInsert(Trigger.new);
            if (Trigger.isUpdate) handler.beforeUpdate(Trigger.new, Trigger.oldMap);
            if (Trigger.isDelete) handler.beforeDelete(Trigger.old);
        }
        if (Trigger.isAfter) {
            if (Trigger.isInsert) handler.afterInsert(Trigger.new, Trigger.newMap);
            if (Trigger.isUpdate) handler.afterUpdate(Trigger.new, Trigger.oldMap);
            if (Trigger.isDelete) handler.afterDelete(Trigger.old, Trigger.oldMap);
            if (Trigger.isUndelete) handler.afterUndelete(Trigger.new);
        }
    }
}
