# Golden Dragon Prague - Business Intelligence Dashboard

## Executive Dashboard Metrics

### 1. Revenue Overview

| Metric | Definition | Source Query |
|--------|-----------|-------------|
| Total Revenue | Sum of all completed order totals | `SELECT SUM(total) FROM Orders WHERE status='completed'` |
| Daily Average | Revenue per day | `SELECT AVG(daily_revenue) FROM v_daily_revenue` |
| Average Order Value | Mean order total | `SELECT AVG(total) FROM Orders WHERE status='completed'` |
| Revenue Growth | Month-over-month % change | `v_monthly_revenue_trends.mom_growth_pct` |
| VAT Collected | 12% of the taxable base | `v_daily_revenue.vat_total` |
| Collection Status | PAID / PARTIAL / UNPAID per order | `v_order_summary.payment_status` |
| Outstanding Balance | Order total minus payments received | `v_order_summary.amount_due` |

Every revenue figure above is measured over **completed orders only** — that is the
filter inside `v_daily_revenue`, and the Python dashboard applies the same one. Do not
compare it against an all-status order count.

The taxable base is `subtotal - discount + delivery_fee`, not the raw subtotal: a
discount reduces what the customer is charged VAT on, and the delivery fee is part of
the service being taxed. `compute_order_totals()` is the single implementation.

**Business Value**: Track financial health, plan cash flow, prepare tax filings,
chase unpaid balances.

### 2. Customer Analytics

| Metric | Definition | Source |
|--------|-----------|--------|
| Total Customers | Count of distinct customers | `v_customer_order_history` |
| New Customers | First-time buyers this period | `get_daily_summary().new_customers` |
| Customer Lifetime Value | Total spent per customer | `get_customer_lifetime_value()` |
| RFM Segment | Recency, Frequency, Monetary tier | `v_customer_rfm` |
| Retention Rate | % returning customers | `v_cohort_retention` |

**Business Value**: Customer acquisition cost analysis, loyalty program effectiveness, churn prevention.

### 3. Menu Performance

| Metric | Definition | Source |
|--------|-----------|--------|
| Top Dish | Most portions sold | `v_top_dishes` |
| Menu Revenue | Total revenue per item | `v_top_dishes.revenue` |
| Avg Selling Price | Mean price per portion | `v_top_dishes.avg_selling_price` |
| Lunch vs Dinner | Revenue comparison | `v_lunch_vs_dinner_analysis` |

**Business Value**: Menu engineering (stars, puzzles, plowhorses, dogs), pricing optimization, inventory planning.

### 4. Operational Efficiency

| Metric | Definition | Source |
|--------|-----------|--------|
| Kitchen Queue | Active orders by status | `v_kitchen_queue` |
| Table Occupancy | % tables in use | `v_table_status` |
| Hourly Demand | Orders by hour/day | `v_hourly_demand_patterns` |
| Kitchen Efficiency | Orders handled per staff | `v_kitchen_efficiency` |
| Avg Prep Time | Time from order to ready | Computed from status timestamps |

**Business Value**: Staff scheduling, kitchen capacity planning, service quality monitoring.

### 5. Safety & Compliance

| Metric | Definition | Source |
|--------|-----------|--------|
| Active Allergen Warnings | Open orders with allergens | `v_allergen_warnings` |
| Low Stock Items | Inventory below threshold | `Inventory` joined to `Menus` (see 08_queries.sql) |
| Audit Trail | Status change log | `OrderAuditLog` |

`v_allergen_warnings` reports both sides: an order carrying allergy notes whose dishes
contain a matching allergen raises a **WARNING**, and one whose dishes are clear is
explicitly marked **SAFE**. Silence is not the same as a clearance, so the kitchen sees
the SAFE rows too.

There is deliberately no `v_inventory_status` view — stock is a two-column lookup and a
view would only hide the threshold. Low stock is a query:

```sql
SELECT m.name_en, i.quantity
FROM Inventory i JOIN Menus m ON m.menu_id = i.menu_id
WHERE i.quantity < 20 ORDER BY i.quantity;
```

**Business Value**: EU allergen compliance, inventory management, dispute resolution.

### 6. Channel Performance

| Metric | Definition | Source |
|--------|-----------|--------|
| Wolt Revenue | Orders via Wolt platform | `v_source_performance` |
| Bolt Revenue | Orders via Bolt platform | `v_source_performance` |
| Walk-in Revenue | In-person orders | `v_source_performance` |
| Platform Fees | Estimated commission | `v_source_performance.estimated_platform_fees` |
| Net Revenue | Revenue minus platform fees | `v_source_performance.estimated_net_revenue` |

Commission is charged **per channel**, not per order. `get_platform_commission_rate()`
returns 22% for `wolt` and `bolt` and 0% for `walk-in`, `phone` and `website`; the rate
is exposed as `platform_commission_rate` so the fee column can always be reconciled.
A dine-in order does not lose 22% to a delivery app, and an earlier flat-rate version of
this view understated in-house net revenue by exactly that much.

**Business Value**: Channel profitability, marketing budget allocation, platform negotiation.

---

## Dashboard Layout (Conceptual)

The figures in this sketch are **illustrative placeholders** showing what a full year of
trading would look like. They are not the seed dataset — run `python scripts/analyze.py`
for the real numbers, which are much smaller by design.

```
┌──────────────────────────────────────────────────────────────┐
│  GOLDEN DRAGON PRAGUE - Executive Dashboard                    │
├──────────┬──────────┬──────────┬──────────┬──────────────────┤
│ Revenue  │ Orders   │ Customers│ Avg Order│ VAT Collected    │
│ 125,430  │   142    │    89    │  883 CZK │  15,050 CZK      │
│ CZK      │          │          │          │                  │
├──────────┴──────────┴──────────┴──────────┴──────────────────┤
│                                                              │
│  Revenue Trend (Line + Bar Chart)                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  [Monthly revenue bars + 3-month moving average line]  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
├──────────────────────────┬───────────────────────────────────┤
│                          │                                   │
│  Customer Segments       │  Top 10 Dishes                    │
│  (Pie Chart)             │  (Horizontal Bar)                 │
│                          │                                   │
├──────────────────────────┼───────────────────────────────────┤
│                          │                                   │
│  Hourly Demand Heatmap   │  Revenue by Channel               │
│  (Day × Hour grid)       │  (Stacked Bar)                    │
│                          │                                   │
├──────────────────────────┴───────────────────────────────────┤
│                                                              │
│  Recent Orders Table                                         │
│  ┌──────┬──────────┬─────────┬────────┬──────────┬────────┐ │
│  │ ID   │ Customer │ Items   │ Total  │ Status   │ Time   │ │
│  ├──────┼──────────┼─────────┼────────┼──────────┼────────┤ │
│  │ 0012 │ Jan N.   │   3     │ 456 CZK│ preparing│ 12:30  │ │
│  │ 0011 │ Petr H.  │   1     │ 199 CZK│ new      │ 12:15  │ │
│  └──────┴──────────┴─────────┴────────┴──────────┴────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## How Metrics Connect to Business Decisions

The insights below are the **actual output of the seed dataset** (15 orders, 10 of them
completed), not invented numbers. They are small, and in one case the honest reading is
"not enough data to conclude anything" — which is itself the point: a dashboard that
manufactures a trend out of ten rows is worse than one that says so.

### Scenario 1: Staff Scheduling
**Metric**: `v_hourly_demand_patterns`
**Insight**: No hour has more than one order, so there is no statistically meaningful
peak yet. What the data *does* show is where the money sits: the 18:00-20:00 dinner band
carries the largest tickets, topped by Tuesday 19:00 at 1,491.84 CZK.
**Action**: Staff to ticket size, not headcount, until volume justifies an hourly model.
Revisit once a few hundred orders have accumulated.

### Scenario 2: Menu Optimization
**Metric**: `v_top_dishes`
**Insight**: Kung Pao Chicken with Rice leads on volume - 6 portions, 1,094 CZK - but its
average selling price (175.67) is below its 189.00 menu price because it is discounted
into the lunch sets.
**Action**: Check whether the lunch-set margin still holds at that effective price, or
promote a higher-margin dish into the set.

### Scenario 3: Customer Retention
**Metric**: `v_cohort_retention`
**Insight**: Of the 4 customers acquired in June 2025, only 1 ordered again in July -
25% month-1 retention, so 75% lapsed.
**Action**: Re-engagement campaign targeting the June cohort; 25% is the baseline any
loyalty change has to beat.

### Scenario 4: Channel Investment
**Metric**: `v_source_performance`
**Insight**: Wolt and Bolt pay the same 22% commission, so the comparison is pure volume:
Wolt delivers 3 orders / 2,358.72 gross / 1,839.80 net, Bolt 1 order / 423.36 gross /
330.22 net. Wolt is the channel that matters; Bolt is close to noise.
**Action**: Concentrate delivery marketing on Wolt, and use its volume as leverage to
negotiate the 22% down - a point off Wolt is worth more than all of Bolt.

### Scenario 5: Inventory Management
**Metric**: `Inventory` (see the low-stock query above)
**Insight**: Peking Duck is down to 11 portions, less than half the next lowest item
(Kung Pao at 24).
**Action**: Place a supplier order before the weekend; Peking Duck is a high-ticket item
and stocking out costs more than the carry.

### Scenario 6: Lunch Strategy
**Metric**: `v_lunch_vs_dinner_analysis`
**Insight**: Lunch is *not* a high-volume / low-value trade-off here - it is low on both.
2 orders at 288.96 average against 8 orders at 682.22 for regular pricing.
**Action**: The lunch window is under-utilised rather than under-priced. Drive footfall
(office marketing, faster service promise) before touching the set price.

---

## Export Formats for BI Tools

### CSV Export (for Tableau, Power BI)
```bash
python scripts/export_csv.py
# Output: samples/dashboard_output/*.csv
```

### JSON Export (for web dashboards)
```sql
-- Example: Order summary as JSON
SELECT json_agg(t) FROM v_order_summary t;
```

### Direct Connection (SAP Analytics Cloud)
```
Protocol:  PostgreSQL
Host:      localhost:5432
Database:  golden_dragon_prague
Schema:    public
```

---

*This dashboard documentation shows how raw database queries translate into business decisions - exactly what SAP data analysts do daily.*
