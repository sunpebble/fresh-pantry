# 0001 — Inventory Row Identity: name × unit × storage × (Batch for Perishables)

When the user intakes a same-named item already in inventory, we merge into the existing row **only for Non-perishables**; for **Perishables** every intake creates a new **Batch** row carrying its own expiry. Same name with different unit or different storage area always stays separate.

We picked this over pure-merge (which silently overwrites older expiries and kills the 临期 signal) and pure-per-batch (which clutters the inventory list with N rows of rice/oil over time). The split keeps expiry tracking accurate where it matters (perishables) without exploding row count where it doesn't.

**Consequence**: `FoodCategory` carries an `isPerishable` flag; all three **Proposal** sources (paste / recipe / shopping) compute the default action against this rule and expose it as an overridable chip in the **Review** screen; the Inventory list needs a long-press "merge two batches" affordance (keep the earlier expiry).
