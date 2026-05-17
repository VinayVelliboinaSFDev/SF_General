# Scenario 01 — Dynamic Discount Validation System

**Difficulty:** Intermediate  
**Category:** Apex / Trigger Framework / Rollup Logic

---

## Business Context

A mid-size sales organization uses Salesforce CPQ-lite patterns built on standard `OpportunityLineItem` (Opportunity Products). Sales reps apply discounts at the line-item level, but leadership needs guardrails:

- Discounts above 20% must go through a manager approval process before the Opportunity can progress.
- Zero-quantity line items bloat pipeline reporting and must be blocked at entry.
- Duplicate products on a single Opportunity create confusion in proposals and must be prevented.
- Finance needs a real-time "Total Discount Amount" field on the Opportunity for dashboards and roll-up reports.

This scenario mirrors real enterprise constraints you will encounter in manufacturing, SaaS, and retail Salesforce orgs.

---

## Requirements

1. **Discount Threshold Validation** — If a rep saves an `OpportunityLineItem` with `Discount > 20`, block the save with an error message instructing them to seek manager approval.
2. **Zero-Quantity Block** — If `Quantity` is `0` or `null`, block the save.
3. **Duplicate Product Prevention** — Within the same Opportunity, two line items cannot share the same `Product2Id`. Block the second insert or update.
4. **Total Discount Rollup** — After any insert, update, or delete of `OpportunityLineItem`, recalculate and write `Total_Discount_Amount__c` on the parent `Opportunity`. Formula: `SUM(UnitPrice * Quantity * Discount / 100)` across all active line items.
5. **Bulk-safe** — All logic must handle batches of 200 records without hitting governor limits.

---

## Acceptance Criteria

| # | Given | When | Then |
|---|-------|------|------|
| 1 | A sales rep edits a line item | Discount field = 25 | Save is blocked; error appears on the Discount field: *"Discounts above 20% require manager approval."* |
| 2 | A rep inserts a new line item | Quantity = 0 | Save is blocked; error: *"Quantity must be greater than zero."* |
| 3 | A rep inserts Product X | Product X already exists on the same Opportunity | Save is blocked; error: *"This product has already been added to the Opportunity."* |
| 4 | Any line item is saved or deleted | — | `Total_Discount_Amount__c` on the parent Opportunity is updated within the same transaction (sync rollup). |
| 5 | A batch of 150 line items across 10 Opportunities is inserted via Data Loader | — | All validations apply; rollup updates all 10 Opportunities in a single DML operation. |

---

## Pre-Deployment / Setup Steps

1. Create the custom field `Total_Discount_Amount__c` (Currency, 16/2) on the `Opportunity` object.
2. Ensure the `OpportunityLineItem` object is enabled (requires at least one active Price Book in the org).
3. Deploy all Apex classes before deploying the trigger.

---

## Implementation Details / Design

### Trigger Framework Pattern

Use a **single trigger per object** dispatching to a dedicated handler class. The handler calls a service/domain class for business logic. This keeps the trigger itself free of logic and makes unit testing straightforward.

```
OpportunityLineItemTrigger (trigger)
    └── OpportunityLineItemTriggerHandler (handler — implements ITriggerHandler)
            └── OpportunityLineItemService (service — pure business logic)
                    └── OpportunityRollupService (rollup utility)
```

**Why this layering?**  
- The trigger is a routing mechanism only — swapping frameworks (e.g., moving to fflib) touches one file.  
- The service is independently testable without a DML context.  
- The rollup service is reusable if other objects ever need to update Opportunity aggregates.

### Before-Insert / Before-Update Logic (OpportunityLineItemService)

```
validateDiscount(List<OpportunityLineItem> newList)
    for each OLI:
        if OLI.Discount > 20 → OLI.addError(Discount, MSG_DISCOUNT_APPROVAL)

validateQuantity(List<OpportunityLineItem> newList)
    for each OLI:
        if OLI.Quantity == null || OLI.Quantity <= 0 → OLI.addError(Quantity, MSG_ZERO_QTY)

validateNoDuplicateProducts(List<OpportunityLineItem> newList, Map<Id,OpportunityLineItem> oldMap)
    1. Collect all OpportunityIds from newList.
    2. Query existing OLIs for those Opps (excluding records being updated — use oldMap keyset).
    3. Build Map<Id, Set<Id>>: OpportunityId → Set of Product2Ids already present.
    4. For each incoming OLI: if its Product2Id already in the set → addError on Product2Id field.
```

**Governor limit note:** The duplicate check requires one SOQL query inside the before context. Collect all Opp IDs first, then issue a single `SELECT Id, OpportunityId, Product2Id FROM OpportunityLineItem WHERE OpportunityId IN :oppIds` — never query inside a loop.

### After-Insert / After-Update / After-Delete Rollup (OpportunityRollupService)

```
recalculateTotalDiscount(Set<Id> opportunityIds)
    1. Query: SELECT OpportunityId, SUM(TotalPrice) totalSale,
                     SUM(UnitPrice * Quantity * Discount / 100) totalDiscount
              FROM OpportunityLineItem
              WHERE OpportunityId IN :opportunityIds
              GROUP BY OpportunityId
    2. Build List<Opportunity> to update with new Total_Discount_Amount__c values.
    3. Single update DML — no per-record DML.
```

**Why after-trigger for rollup?**  
The rollup reads committed or about-to-commit data. Doing it in `after` ensures the current transaction's OLIs (including deletes) are reflected in the aggregate query.

### Trade-offs / Interview Talking Points

| Approach | Pro | Con |
|----------|-----|-----|
| Apex rollup (this scenario) | Real-time, bulk-safe | Counts against DML/SOQL limits |
| Roll-Up Summary field | Zero code | Only works for Master-Detail; OLI→Opp is already M-D — could use DLRS for flexibility |
| Platform Event + async | Avoids after-trigger SOQL cost | Eventual consistency; dashboard lags |

For a portfolio, implementing the Apex rollup and *documenting* the trade-offs is the most impressive choice.

---

## Salesforce Artifacts

| Artifact | API Name / Value | Notes |
|----------|-----------------|-------|
| Custom Field | `Opportunity.Total_Discount_Amount__c` | Currency, 16,2 |
| Apex Trigger | `OpportunityLineItemTrigger` | On `OpportunityLineItem`; all events |
| Apex Class | `OpportunityLineItemTriggerHandler` | Implements `ITriggerHandler` |
| Apex Class | `OpportunityLineItemService` | Business logic; `@TestVisible` private methods |
| Apex Class | `OpportunityRollupService` | Shared rollup utility |
| Apex Class | `ITriggerHandler` | Interface: `beforeInsert()`, `beforeUpdate()`, `afterInsert()`, etc. |
| Apex Class | `TriggerDispatcher` | Framework entry point |
| Apex Test | `OpportunityLineItemTriggerTest` | Uses `TestDataFactory` |
| Apex Test | `OpportunityRollupServiceTest` | Isolated rollup unit tests |
| Apex Class | `TestDataFactory` | Shared across all scenarios |

---

## Testing Strategy

### Test Data Factory Usage
```apex
// TestDataFactory creates Account → Opportunity → PricebookEntry chain
Account acc = TestDataFactory.createAccount('Acme');
Opportunity opp = TestDataFactory.createOpportunity(acc.Id, 'Test Deal', Date.today().addDays(30));
Product2 prod = TestDataFactory.createProduct('Widget Pro');
PricebookEntry pbe = TestDataFactory.createPricebookEntry(prod.Id);
```

### Test Scenarios to Cover

| Test Method | What it proves |
|-------------|---------------|
| `testDiscountOver20BlocksSave` | `addError` fires on Discount field |
| `testZeroQuantityBlocksSave` | `addError` fires on Quantity field |
| `testDuplicateProductBlocksInsert` | Duplicate check queries correctly |
| `testDuplicateProductAllowsUpdate` | Updating an existing OLI doesn't false-positive |
| `testRollupOnInsert` | `Total_Discount_Amount__c` is correct after insert |
| `testRollupOnUpdate` | Rollup recalculates on discount change |
| `testRollupOnDelete` | Rollup recalculates on line item removal |
| `testBulk200Records` | All validations and rollup work with 200 OLIs across 10 Opps |

### Mocking / Isolation
- Callout mocks: not applicable.
- Use `Test.startTest()` / `Test.stopTest()` around DML to get fresh governor limit counts.
- Keep `TestDataFactory` methods as `static` so they compose cleanly.

---

## README Highlights / GitHub Showcase

**What to call out in the README:**
- The trigger framework pattern (link to `ITriggerHandler` and `TriggerDispatcher`).
- The single-SOQL bulk-safe duplicate check.
- The after-trigger aggregate rollup vs. DLRS trade-off note.

**Diagram (Mermaid):**
```
flowchart TD
    T[OpportunityLineItemTrigger] --> H[Handler]
    H --> S[OpportunityLineItemService]
    S -->|Before| V1[validateDiscount]
    S -->|Before| V2[validateQuantity]
    S -->|Before| V3[validateNoDuplicateProducts]
    H --> R[OpportunityRollupService]
    R -->|After insert/update/delete| U[Update Opportunity.Total_Discount_Amount__c]
```
