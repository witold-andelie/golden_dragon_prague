# Golden Dragon Prague - Business Intelligence Dashboard

## Executive Dashboard Metrics

### 1. Revenue Overview

| Metric | Definition | Source Query |
|--------|-----------|-------------|
| Total Revenue | Sum of all completed order totals | `SELECT SUM(total) FROM Orders WHERE status='completed'` |
| Daily Average | Revenue per day | `SELECT AVG(daily_revenue) FROM v_daily_revenue` |
| Average Order Value | Mean order total | `SELECT AVG(total) FROM Orders WHERE status='completed'` |
| Revenue Growth | Month-over-month % change | `v_monthly_revenue_trends.mom_growth_pct` |
| VAT Collected | 12% of subtotals | `v_daily_revenue.vat_total` |

**Business Value**: Track financial health, plan cash flow, prepare tax filings.

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
| Low Stock Items | Inventory below threshold | `v_inventory_status` |
| Audit Trail | Status change log | `OrderAuditLog` |

**Business Value**: EU allergen compliance, inventory management, dispute resolution.

### 6. Channel Performance

| Metric | Definition | Source |
|--------|-----------|--------|
| Wolt Revenue | Orders via Wolt platform | `v_source_performance` |
| Bolt Revenue | Orders via Bolt platform | `v_source_performance` |
| Walk-in Revenue | In-person orders | `v_source_performance` |
| Platform Fees | Estimated commission | `v_source_performance.estimated_platform_fees` |
| Net Revenue | Revenue minus platform fees | `v_source_performance.estimated_net_revenue` |

**Business Value**: Channel profitability, marketing budget allocation, platform negotiation.

---

## Dashboard Layout (Conceptual)

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

### Scenario 1: Staff Scheduling
**Metric**: `v_hourly_demand_patterns`
**Insight**: Friday 18:00-20:00 is peak demand
**Action**: Schedule extra waiters and kitchen staff for Friday evenings

### Scenario 2: Menu Optimization
**Metric**: `v_top_dishes`
**Insight**: Kung Pao Chicken is #1 but has low profit margin
**Action**: Adjust pricing or promote higher-margin items

### Scenario 3: Customer Retention
**Metric**: `v_cohort_retention`
**Insight**: 40% of customers acquired in January don't return
**Action**: Launch re-engagement campaign for lapsed customers

### Scenario 4: Channel Investment
**Metric**: `v_source_performance`
**Insight**: Bolt has higher net revenue than Wolt after fees
**Action**: Increase marketing on Bolt, renegotiate Wolt terms

### Scenario 5: Inventory Management
**Metric**: `v_inventory_status`
**Insight**: Peking Duck stock at 15 portions (critical)
**Action**: Place emergency order with supplier

### Scenario 6: Lunch Strategy
**Metric**: `v_lunch_vs_dinner_analysis`
**Insight**: Lunch orders have 30% lower AOV but higher volume
**Action**: Optimize lunch menu for speed and margin

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
