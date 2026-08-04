# Golden Dragon Prague - Interview Guide

**How to talk about this project in SAP Data Analysis interviews**

---

## The 60-Second Pitch

> "I built a complete PostgreSQL database for a Chinese restaurant in Prague. It handles the full business lifecycle: orders, inventory, reservations, payments, and loyalty programs. What makes it stand out is the depth of business logic encoded directly in the database through PL/pgSQL functions and triggers, plus an analytics layer with RFM customer segmentation, cohort analysis, and revenue forecasting. I also built a star schema for BI reporting and a Python connector that exports data for visualization."

---

## Table-by-Table Explanation (30 seconds each)

### Users
- **Purpose**: Customer accounts with loyalty points
- **Key Design**: `role` column distinguishes customers, staff, VIPs
- **Interview Point**: "I separate customers from employees because they have different attributes. Customers need loyalty points and dietary preferences; employees need roles and hire dates."

### Menus
- **Purpose**: Dishes with dual pricing (regular vs lunch)
- **Key Design**: `price_lunch` is nullable - only items with lunch specials have a value
- **Interview Point**: "Time-based pricing is a real business rule. Lunch specials apply Mon-Fri 11-14:30. The `get_effective_price()` function handles this dynamically."

### OrderDetails
- **Purpose**: Line items - one row per menu item per order
- **Key Design**: `unit_price` captures price at order time (supports price history)
- **Interview Point**: "I don't store just the menu_id and quantity. I capture the price at the moment of order because menu prices change over time. This is important for historical reporting."

### Orders
- **Purpose**: Central business entity
- **Key Design**: JSONB for flexible metadata, status enum for workflow
- **Interview Point**: "The `special_requests` JSONB field stores varying customer requirements - diet preferences, allergy notes, spice levels. This avoids adding 20 nullable columns for rare attributes."

### Inventory
- **Purpose**: Stock levels
- **Key Design**: `quantity >= 0` CHECK constraint
- **Interview Point**: "I enforce non-negative stock at the database level with a CHECK constraint, and also validate in a BEFORE trigger. Defense in depth."

### Events
- **Purpose**: Private events and large catering orders
- **Key Design**: Linked to Orders for billing
- **Interview Point**: "Events are separate from regular orders because they have unique attributes like expected_guests and setup_notes, and often require different workflow handling."

---

## Function-by-Function Explanation (1 minute each)

### compute_order_totals()
- **What it does**: Calculates subtotal + 12% VAT + final total
- **Why**: Czech restaurant VAT = 12% (reduced rate)
- **Interview Point**: "This is a pure function - no side effects. It's called by the trigger after each line item is added, ensuring totals are always up-to-date."

### get_effective_price()
- **What it does**: Returns lunch price if within lunch window, else regular
- **Why**: Business rule for time-based pricing
- **Interview Point**: "This function encapsulates the lunch special rule: Mon-Fri 11:00-14:30. If it's outside that window, or the item has no lunch price, it returns regular price. This keeps pricing logic in one place."

### finalize_order()
- **What it does**: Recalculates totals, applies delivery fee
- **Why**: Delivery orders under 350 CZK get +49 CZK fee
- **Interview Point**: "This function demonstrates how business rules cascade. It calls `compute_order_totals()` internally, then applies the delivery fee rule. This is called automatically by a trigger."

### is_table_available() + create_reservation()
- **What it does**: Prevents double-booking tables
- **Why**: Core restaurant operation
- **Interview Point**: "The availability check uses a 2-hour overlap buffer. If a reservation starts before ours ends AND ends after ours starts, it's a conflict. The `create_reservation()` function wraps this with an exception for atomic safety."

---

## Trigger-by-Trigger Explanation (1 minute each)

### trg_check_inventory (BEFORE INSERT)
- **Purpose**: Validates stock before order
- **Pattern**: Validation trigger
- **Interview Point**: "This is a BEFORE trigger that raises an exception if stock is insufficient. It prevents the order from being created at all - fail-fast principle."

### trg_set_unit_price (BEFORE INSERT)
- **Purpose**: Applies dynamic pricing
- **Pattern**: Data preparation trigger
- **Interview Point**: "This modifies the NEW row before insert, setting the correct unit_price based on current time. This ensures price consistency even if the menu price changes later."

### trg_after_order_detail (AFTER INSERT)
- **Purpose**: Deducts inventory, recalculates totals
- **Pattern**: Side-effect trigger
- **Interview Point**: "This is an AFTER trigger because it needs the row to exist first. It deducts inventory and calls `finalize_order()` to recalculate totals. This is where the cascading business logic happens."

### trg_order_status (AFTER UPDATE)
- **Purpose**: Validates status + awards loyalty points
- **Pattern**: Conditional trigger with WHEN clause
- **Interview Point**: "I use a WHEN clause to fire only when status actually changes - efficient. It prevents invalid transitions (e.g., 'out_for_delivery' only for delivery orders) and awards loyalty points on completion."

### trg_reservation_check (BEFORE INSERT/UPDATE)
- **Purpose**: Prevents overlapping reservations
- **Pattern**: Validation trigger
- **Interview Point**: "This fires before insert or update on Reservations. It calls `is_table_available()` and raises an exception on conflict. This is how you enforce complex business rules at the database level."

---

## Analytics Deep Dive (2 minutes each)

### RFM Customer Segmentation
```sql
-- The query in v_customer_rfm
NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score
NTILE(5) OVER (ORDER BY frequency) AS f_score
NTILE(5) OVER (ORDER BY monetary) AS m_score
```
- **Interview Point**: "RFM is a standard CRM technique. I use NTILE to divide customers into quintiles for each dimension. Then I combine them into segments: Champions (high R+F+M), At Risk (low R but high F), etc."

### Cohort Analysis
```sql
-- v_cohort_retention
DATE_TRUNC('month', MIN(order_time)) AS cohort_month
COUNT(DISTINCT user_id) FILTER (WHERE activity_month = cohort_month + '1 month') AS month_1_retention
```
- **Interview Point**: "Cohort analysis shows customer retention over time. I group customers by their first purchase month, then track what percentage return in subsequent months. This is crucial for understanding customer lifecycle."

### Revenue Forecasting
```sql
-- v_revenue_forecast
AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma_7d
LAG(revenue, 7) OVER (ORDER BY day) AS same_day_last_week
```
- **Interview Point**: "I use a 7-day moving average for short-term forecasting and compare with same day last week to account for weekly seasonality. For longer trends, a 30-day MA smooths out noise."

### Pareto Analysis (80/20 Rule)
```sql
SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) AS cumulative_pct
```
- **Interview Point**: "The Pareto principle: 20% of customers generate 80% of revenue. I use a running total with window functions to find exactly where that threshold is. This informs marketing budget allocation."

---

## Star Schema Explanation

### Why Star Schema?
- **Interview Point**: "The operational database is in 3NF for data integrity. But for analytics, a star schema is more efficient. Pre-joined dimensions mean BI tools can slice and dice without complex joins."

### Grain Definition
- **Interview Point**: "The fact table grain is 'one row per order line item'. This means an order with 3 items produces 3 rows. This granularity enables analysis like 'which menu items are frequently ordered together?'"

### Slowly Changing Dimensions
- **Interview Point**: "Customer attributes can change (email, loyalty tier). SCD Type 2 preserves history by creating new rows with validity periods. This lets me ask 'what was this customer's tier when they placed order X?'"

---

## Common Interview Questions & Answers

### "Why PostgreSQL?"
> "PostgreSQL has the best JSONB support of any relational database. The special_requests field in orders varies wildly - dietary restrictions, allergy notes, delivery instructions. JSONB lets me store this flexibly while still supporting indexing and efficient queries. Plus PL/pgSQL is powerful for encoding business logic."

### "How do you ensure data integrity?"
> "Defense in depth: CHECK constraints at the schema level, BEFORE triggers for validation, foreign keys for referential integrity, and an audit trail table for change tracking. For example, inventory can't go negative because of both a CHECK constraint and a BEFORE trigger that validates stock."

### "Explain your indexing strategy."
> "I use B-tree indexes on high-cardinality columns used in WHERE clauses (status, time, user_id). The GIN index on JSONB is critical - without it, JSONB queries do sequential scans. I also have composite indexes for common query patterns like date + status for revenue reports."

### "How would you scale this?"
> "For read scaling, I'd add read replicas. For write scaling, I'd partition Orders by month. The JSONB fields would get expression indexes for specific keys. For the analytics layer, materialized views with scheduled refreshes would reduce query load."

### "What's your approach to query optimization?"
> "I always start with EXPLAIN ANALYZE to see the actual execution plan. For this project, I verified that the GIN index is used for JSONB queries and B-tree indexes for status/time filters. I avoid SELECT * in production and use covering indexes where possible."

### "How do you handle schema changes?"
> "The JSONB columns (special_requests, delivery_address) handle variable attributes without schema changes. For structural changes, I'd use versioned migrations. The star schema dimensions are designed to handle slowly changing attributes via SCD Type 2."

### "Describe your data modeling approach."
> "I start with 3NF for operational tables to ensure data integrity. For analytics, I layer a star schema on top. The key trade-off is between normalization (no redundancy, complex joins) and denormalization (fast reads, some redundancy). I use normalization for OLTP and denormalization for OLAP."

### "What BI/metrics did you build?"
> "I built 11 analytics views covering: RFM customer segmentation, cohort retention, revenue trends with moving averages, hourly demand patterns for staffing, channel profitability analysis, and VAT breakdowns for tax reporting. These directly support business decisions."

### "How do you connect databases to analytics tools?"
> "I built a Python connector using psycopg2 that exports all views to CSV. It also generates an HTML dashboard with embedded charts using matplotlib. This demonstrates the full pipeline from database to business intelligence."

---

## Technical Depth Points (for advanced questioning)

### JSONB vs Separate Columns
> "JSONB is better when: (1) attributes are sparse (most orders don't have dietary notes), (2) schema evolves frequently (new special request types), (3) you need flexible querying. Separate columns are better when attributes are mandatory or heavily indexed."

### Trigger Performance
> "Triggers add latency to writes. For this project, the AFTER trigger on OrderDetails does two UPDATEs (inventory + order totals). In high-volume systems, I'd move this to an async queue or use materialized views refreshed on schedule."

### Materialized Views
> "The `mv_daily_kpi` view pre-computes daily KPIs. I refresh it after ETL. Trade-off: data is slightly stale (refreshed daily) but queries are instant. For real-time dashboards, I'd use incremental refresh or a streaming approach."

### Window Functions vs Self-Join
> "Window functions are almost always better than self-joins for running totals and rankings. They compute in a single pass, are more readable, and the optimizer handles them well."

---

## Project Metrics to Mention

| Metric | Value | Why It Matters |
|--------|-------|---------------|
| Tables | 13 | Full data model coverage |
| Functions | 10 | Business logic in database |
| Triggers | 7 | Automated data integrity |
| Views | 19 | Operational + BI coverage |
| Indexes | 14+ | Query optimization |
| ETL Procedures | 3 | Data pipeline automation |
| Lines of SQL | ~2000+ | Comprehensive implementation |
| Sample Records | 80+ | Realistic test data |

---

## Questions to Ask the Interviewer

1. "Does SAP use PostgreSQL or primarily SAP HANA?"
2. "What BI tools does the team use for reporting?"
3. "Are there existing ETL frameworks I should know about?"
4. "How much of the analytics work is SQL-based vs Python/R?"
5. "What's the typical data volume - is partitioning a concern?"

---

*This guide covers the most likely interview topics. Practice explaining each component out loud - you should be able to describe any table, function, or view in under 2 minutes with clear business context.*
