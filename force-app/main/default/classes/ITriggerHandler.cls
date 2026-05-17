/**
 * ITriggerHandler
 * Interface that every trigger handler must implement.
 * Each method corresponds to one trigger context. Handlers only override
 * the contexts they care about — the dispatcher calls all of them safely.
 */
public interface ITriggerHandler {
    void beforeInsert(List<SObject> newList);
    void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap);
    void beforeDelete(List<SObject> oldList);
    void afterInsert(List<SObject> newList, Map<Id, SObject> oldMap);
    void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap);
    void afterDelete(List<SObject> oldList, Map<Id, SObject> oldMap);
    void afterUndelete(List<SObject> newList);
}
