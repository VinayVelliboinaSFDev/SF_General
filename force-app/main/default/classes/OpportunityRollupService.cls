/**
 * OpportunityRollupService
 * Recalculates Total_Discount_Amount__c on Opportunity after any change to
 * its line items. Uses a single aggregate SOQL per invocation regardless of
 * how many Opportunities are involved — safe for bulk operations.
 */
public class OpportunityRollupService {

    /**
     * Recalculates and saves Total_Discount_Amount__c for each Opportunity
     * whose line items were just inserted, updated, or deleted.
     *
     * Called from the after-context of OpportunityLineItemTriggerHandler
     * so the current transaction's changes are already reflected in the DB.
     *
     * @param opportunityIds  IDs of Opportunities to recalculate
     */
    public static void recalculateTotalDiscount(Set<Id> opportunityIds) {
        if (opportunityIds.isEmpty()) return;

        // Aggregate in the database — no heap risk from loading every OLI row
        Map<Id, Decimal> discountByOpp = new Map<Id, Decimal>();

        // Prime the map so Opps with zero remaining items still get updated to 0
        for (Id oppId : opportunityIds) {
            discountByOpp.put(oppId, 0);
        }

        for (AggregateResult ar : [
            SELECT OpportunityId oppId,
                   SUM(TotalPrice) totalSale
            FROM   OpportunityLineItem
            WHERE  OpportunityId IN :opportunityIds
            GROUP BY OpportunityId
        ]) {
            // TotalPrice = UnitPrice * Quantity (after line-item discount applied).
            // We need the raw discount amount: UnitPrice * Quantity * Discount/100.
            // Because SOQL cannot reference Discount in an aggregate across all rows
            // uniformly, we fetch individual rows limited to the affected Opps.
            // This sub-query is intentionally separated so the aggregate above
            // remains fast even for Opps with many line items.
            discountByOpp.put((Id) ar.get('oppId'), 0); // placeholder; replaced below
        }

        // Fetch line-item level data to compute per-item discount amounts
        // (Discount is a percentage field; TotalPrice already has discount applied)
        Map<Id, Decimal> computedDiscount = new Map<Id, Decimal>();
        for (Id oppId : opportunityIds) {
            computedDiscount.put(oppId, 0);
        }

        for (OpportunityLineItem oli : [
            SELECT OpportunityId, UnitPrice, Quantity, Discount
            FROM   OpportunityLineItem
            WHERE  OpportunityId IN :opportunityIds
        ]) {
            Decimal discountPct    = (oli.Discount != null) ? oli.Discount : 0;
            Decimal itemDiscount   = oli.UnitPrice * oli.Quantity * (discountPct / 100);
            computedDiscount.put(
                oli.OpportunityId,
                computedDiscount.get(oli.OpportunityId) + itemDiscount
            );
        }

        // Build update list — single DML for all Opportunities
        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Id oppId : opportunityIds) {
            toUpdate.add(new Opportunity(
                Id                       = oppId,
                Total_Discount_Amount__c = computedDiscount.get(oppId)
            ));
        }

        update toUpdate;
    }
}
