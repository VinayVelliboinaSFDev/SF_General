/**
 * OpportunityLineItemService
 * Pure business logic for Opportunity Line Item rules. No DML here — callers
 * are responsible for DML so this class stays unit-testable in isolation.
 */
public class OpportunityLineItemService {

    @TestVisible private static final String MSG_DISCOUNT_APPROVAL =
        'Discounts above 20% require manager approval. Please contact your manager.';
    @TestVisible private static final String MSG_ZERO_QTY =
        'Quantity must be greater than zero.';
    @TestVisible private static final String MSG_DUPLICATE_PRODUCT =
        'This product has already been added to the Opportunity.';

    // ─── Validation: Before Insert / Update ──────────────────────────────

    /**
     * Blocks save when Discount > 20. Error is attached to the Discount
     * field so it surfaces inline on the page layout.
     */
    public static void validateDiscount(List<OpportunityLineItem> newList) {
        for (OpportunityLineItem oli : newList) {
            if (oli.Discount != null && oli.Discount > 20) {
                oli.Discount.addError(MSG_DISCOUNT_APPROVAL);
            }
        }
    }

    /**
     * Blocks save when Quantity is null or zero.
     */
    public static void validateQuantity(List<OpportunityLineItem> newList) {
        for (OpportunityLineItem oli : newList) {
            if (oli.Quantity == null || oli.Quantity <= 0) {
                oli.Quantity.addError(MSG_ZERO_QTY);
            }
        }
    }

    /**
     * Prevents two line items with the same Product2Id on the same Opportunity.
     *
     * Strategy:
     *   1. One SOQL query fetches all existing OLIs for the affected Opps.
     *   2. Records being updated are excluded from the "existing" set so a rep
     *      can save an existing OLI without triggering a false duplicate error.
     *   3. The incoming batch is also checked against itself to catch two new
     *      rows for the same product inserted simultaneously.
     *
     * @param newList  Trigger.new
     * @param oldMap   Trigger.oldMap (null on insert)
     */
    public static void validateNoDuplicateProducts(
        List<OpportunityLineItem> newList,
        Map<Id, OpportunityLineItem> oldMap
    ) {
        // Collect the Opportunity IDs we need to check
        Set<Id> oppIds = new Set<Id>();
        for (OpportunityLineItem oli : newList) {
            oppIds.add(oli.OpportunityId);
        }

        // IDs of records currently being updated — exclude from existing set
        Set<Id> updatingIds = (oldMap != null) ? oldMap.keySet() : new Set<Id>();

        // Build a map: OpportunityId → Set<Product2Id> of already-saved products
        Map<Id, Set<Id>> existingProductsByOpp = new Map<Id, Set<Id>>();
        for (OpportunityLineItem existing : [
            SELECT Id, OpportunityId, Product2Id
            FROM   OpportunityLineItem
            WHERE  OpportunityId IN :oppIds
              AND  Id NOT IN :updatingIds
        ]) {
            if (!existingProductsByOpp.containsKey(existing.OpportunityId)) {
                existingProductsByOpp.put(existing.OpportunityId, new Set<Id>());
            }
            existingProductsByOpp.get(existing.OpportunityId).add(existing.Product2Id);
        }

        // Also track products seen within the current batch to catch bulk duplicates
        Map<Id, Set<Id>> seenInBatch = new Map<Id, Set<Id>>();

        for (OpportunityLineItem oli : newList) {
            Set<Id> existing = existingProductsByOpp.get(oli.OpportunityId);
            Set<Id> inBatch  = seenInBatch.get(oli.OpportunityId);

            Boolean duplicateInDb    = (existing != null && existing.contains(oli.Product2Id));
            Boolean duplicateInBatch = (inBatch  != null && inBatch.contains(oli.Product2Id));

            if (duplicateInDb || duplicateInBatch) {
                oli.Product2Id.addError(MSG_DUPLICATE_PRODUCT);
            } else {
                // Register this product so subsequent rows in the batch can detect dupes
                if (inBatch == null) {
                    seenInBatch.put(oli.OpportunityId, new Set<Id>{ oli.Product2Id });
                } else {
                    inBatch.add(oli.Product2Id);
                }
            }
        }
    }
}
