/**
 * OpportunityLineItemTriggerHandler
 * Routes trigger events to the appropriate service methods.
 * Contains no business logic — it is purely a coordinator.
 */
public class OpportunityLineItemTriggerHandler implements ITriggerHandler {

    public void beforeInsert(List<SObject> newList) {
        List<OpportunityLineItem> olis = (List<OpportunityLineItem>) newList;
        OpportunityLineItemService.validateDiscount(olis);
        OpportunityLineItemService.validateQuantity(olis);
        OpportunityLineItemService.validateNoDuplicateProducts(olis, null);
    }

    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        List<OpportunityLineItem> olis = (List<OpportunityLineItem>) newList;
        Map<Id, OpportunityLineItem> oldOliMap = (Map<Id, OpportunityLineItem>) oldMap;
        OpportunityLineItemService.validateDiscount(olis);
        OpportunityLineItemService.validateQuantity(olis);
        OpportunityLineItemService.validateNoDuplicateProducts(olis, oldOliMap);
    }

    public void beforeDelete(List<SObject> oldList) {}

    public void afterInsert(List<SObject> newList, Map<Id, SObject> oldMap) {
        OpportunityRollupService.recalculateTotalDiscount(collectOppIds(newList));
    }

    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        OpportunityRollupService.recalculateTotalDiscount(collectOppIds(newList));
    }

    public void afterDelete(List<SObject> oldList, Map<Id, SObject> oldMap) {
        OpportunityRollupService.recalculateTotalDiscount(collectOppIds(oldList));
    }

    public void afterUndelete(List<SObject> newList) {
        OpportunityRollupService.recalculateTotalDiscount(collectOppIds(newList));
    }

    // ─── Private Helpers ─────────────────────────────────────────────────

    private Set<Id> collectOppIds(List<SObject> records) {
        Set<Id> ids = new Set<Id>();
        for (SObject record : records) {
            ids.add((Id) record.get('OpportunityId'));
        }
        return ids;
    }
}
