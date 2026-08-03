-- ============================================================
-- Golden Dragon Prague - Advanced Analytics Views
--
-- These views implement business intelligence patterns directly
-- in PostgreSQL, demonstrating data analytics capabilities.
--
-- Key Patterns Demonstrated:
-- 1. RFM Customer Segmentation (Recency, Frequency, Monetary)
-- 2. Cohort Analysis (customer retention by first purchase month)
-- 3. Window Functions (running totals, moving averages, rankings)
-- 4. CTEs (complex multi-step aggregations)
-- 5. Date Truncation (time-series analysis)
-- 6. Pivot-like aggregations (FILTER clause)
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/06_analytics_views.sql
-- ============================================================

-- ============================================================
-- ANALYTICS VIEW 1: v_customer_rfm
-- RFM Customer Segmentation
--
-- R = Recency: days since last order
-- F = Frequency: number of completed orders
-- M = Monetary: total lifetime value
--
-- Segments:
--   Champions:     R=4-5 (recent), F=4-5 (frequent), M=4-5 (high value)
--   Loyal:         R=3-5, F=3-5, M=3-5
--   At Risk:       R=1-2 (not recent), F>=3 (was frequent)
--   Lost:          R=1-2, F=1-2 (recently gone)
--   New:           R=4-5, F=1-2 (recent but not frequent yet)
--
-- Business Use: Targeted marketing campaigns, loyalty program tiers
-- ============================================================
CREATE OR REPLACE VIEW v_customer_rfm AS
WITH rfm_base AS (
    SELECT
        u.user_id,
        u.full_name,
        u.email,
        u.loyalty_points,
        -- Recency: days since last completed order
        COALESCE(
            EXTRACT(EPOCH FROM (NOW() - MAX(o.order_time))) / 86400,
            999
        )::INT AS recency_days,
        -- Frequency: number of completed orders
        COUNT(o.order_id)::INT AS frequency,
        -- Monetary: total lifetime value
        COALESCE(SUM(o.total), 0) AS monetary
    FROM Users u
    LEFT JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    WHERE u.role IN ('customer', 'vip')   -- 'vip' is a customer tier, not a separate audience
    GROUP BY u.user_id, u.full_name, u.email, u.loyalty_points
),
rfm_scores AS (
    SELECT
        *,
        -- Score each dimension 1-5 using NTILE (quartile-based)
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,  -- lower days = higher score
        NTILE(5) OVER (ORDER BY frequency) AS f_score,
        NTILE(5) OVER (ORDER BY monetary) AS m_score
    FROM rfm_base
),
rfm_segments AS (
    SELECT
        *,
        -- Combined RFM score (concatenated, e.g., "555" = champion)
        (r_score * 100 + f_score * 10 + m_score)::TEXT AS rfm_score,
        -- Segment assignment
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customer'
            WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customer'
            ELSE 'Potential'
        END AS segment
    FROM rfm_scores
)
SELECT * FROM rfm_segments ORDER BY monetary DESC;

COMMENT ON VIEW v_customer_rfm IS 'RFM customer segmentation using NTILE quartiles. Champions = recent + frequent + high value. Core CRM analytics view.';

-- ============================================================
-- ANALYTICS VIEW 2: v_cohort_retention
-- Customer Retention by Cohort (first purchase month)
--
-- Shows: How many customers from each month return in subsequent months
-- Business Use: Customer retention strategy, marketing ROI measurement
-- ============================================================
CREATE OR REPLACE VIEW v_cohort_retention AS
WITH customer_cohorts AS (
    -- Assign each customer to their first purchase month
    SELECT
        u.user_id,
        DATE_TRUNC('month', MIN(o.order_time))::DATE AS cohort_month
    FROM Users u
    JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    GROUP BY u.user_id
),
cohort_activity AS (
    -- For each customer, find which months they made purchases
    SELECT
        cc.user_id,
        cc.cohort_month,
        DATE_TRUNC('month', o.order_time)::DATE AS activity_month
    FROM customer_cohorts cc
    JOIN Orders o ON cc.user_id = o.user_id AND o.status = 'completed'
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT user_id) AS cohort_size
    FROM customer_cohorts
    GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    cs.cohort_size,
    ca.activity_month,
    -- Months since first purchase
    EXTRACT(YEAR FROM AGE(ca.activity_month, ca.cohort_month)) * 12
        + EXTRACT(MONTH FROM AGE(ca.activity_month, ca.cohort_month)) AS months_since_first,
    COUNT(DISTINCT ca.user_id) AS active_customers,
    ROUND(
        COUNT(DISTINCT ca.user_id)::NUMERIC / cs.cohort_size * 100,
        2
    ) AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.cohort_size, ca.activity_month
ORDER BY ca.cohort_month, ca.activity_month;

COMMENT ON VIEW v_cohort_retention IS 'Customer retention by acquisition cohort. Shows what % of customers acquired in month N return in month N+1, N+2, etc.';

-- ============================================================
-- ANALYTICS VIEW 3: v_monthly_revenue_trends
-- Monthly revenue with trend analysis
--
-- Includes: rolling averages, month-over-month growth, year-over-year
-- Business Use: Financial planning, growth tracking
-- ============================================================
CREATE OR REPLACE VIEW v_monthly_revenue_trends AS
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_time)::DATE AS month,
        COUNT(*) AS orders_count,
        SUM(total) AS revenue,
        SUM(vat_amount) AS vat_collected,
        SUM(delivery_fee) AS delivery_revenue,
        COUNT(DISTINCT user_id) AS unique_customers,
        AVG(total) AS avg_order_value
    FROM Orders
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('month', order_time)
)
SELECT
    month,
    orders_count,
    revenue,
    vat_collected,
    delivery_revenue,
    unique_customers,
    ROUND(avg_order_value, 2) AS avg_order_value,
    -- Month-over-month growth
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month)) /
        NULLIF(LAG(revenue) OVER (ORDER BY month), 0) * 100,
        2
    ) AS mom_growth_pct,
    -- 3-month rolling average
    ROUND(
        AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        2
    ) AS rolling_3mo_avg,
    -- Cumulative revenue
    SUM(revenue) OVER (ORDER BY month) AS cumulative_revenue
FROM monthly
ORDER BY month;

COMMENT ON VIEW v_monthly_revenue_trends IS 'Monthly revenue trends with MoM growth, 3-month rolling average, and cumulative totals. Used for financial planning.';

-- ============================================================
-- ANALYTICS VIEW 4: v_hourly_demand_patterns
-- Hourly demand distribution (for staffing optimization)
--
-- Shows which hours are busiest on each day of week
-- Business Use: Staff scheduling, kitchen prep planning
-- ============================================================
CREATE OR REPLACE VIEW v_hourly_demand_patterns AS
SELECT
    EXTRACT(DOW FROM order_time)::INT AS day_of_week,  -- 0=Sunday
    TO_CHAR(order_time, 'FMDay') AS weekday_name,
    EXTRACT(HOUR FROM order_time)::INT AS hour_of_day,
    COUNT(*) AS order_count,
    SUM(total) AS revenue,
    COUNT(DISTINCT user_id) AS unique_customers,
    AVG(total) AS avg_order_value
FROM Orders
WHERE status = 'completed'
GROUP BY
    EXTRACT(DOW FROM order_time),
    TO_CHAR(order_time, 'FMDay'),
    EXTRACT(HOUR FROM order_time)
ORDER BY day_of_week, hour_of_day;

COMMENT ON VIEW v_hourly_demand_patterns IS 'Hourly demand by day of week. Used for staff scheduling: shows peak hours needing more waiters/kitchen staff.';

-- ============================================================
-- ANALYTICS VIEW 5: v_source_performance
-- Revenue attribution by channel (Wolt vs Bolt vs walk-in)
--
-- Business Use: Channel profitability analysis, marketing budget allocation
-- ============================================================
CREATE OR REPLACE VIEW v_source_performance AS
SELECT
    source,
    order_type,
    COUNT(*) AS orders,
    SUM(total) AS gross_revenue,
    SUM(delivery_fee) AS delivery_fees_earned,
    SUM(vat_amount) AS vat_collected,
    AVG(total) AS avg_order_value,
    -- Delivery cost estimate: platform takes ~20-25%
    ROUND(SUM(total) * 0.22, 2) AS estimated_platform_fees,
    ROUND(SUM(total) * 0.78, 2) AS estimated_net_revenue
FROM Orders
WHERE status = 'completed'
GROUP BY source, order_type
ORDER BY gross_revenue DESC;

COMMENT ON VIEW v_source_performance IS 'Channel profitability analysis. Estimates platform fees (Wolt/Bolt ~22%). Shows which channels drive most net revenue.';

-- ============================================================
-- ANALYTICS VIEW 6: v_lunch_vs_dinner_analysis
-- Lunch vs dinner pricing impact
--
-- Business Use: Evaluate lunch special pricing strategy
-- ============================================================
CREATE OR REPLACE VIEW v_lunch_vs_dinner_analysis AS
SELECT
    CASE
        WHEN EXTRACT(HOUR FROM order_time) BETWEEN 11 AND 14
             AND EXTRACT(ISODOW FROM order_time) BETWEEN 1 AND 5
        THEN 'Lunch Special'
        ELSE 'Regular Pricing'
    END AS pricing_period,
    COUNT(*) AS orders,
    SUM(od.quantity) AS portions,
    SUM(od.quantity * od.unit_price) AS revenue,
    ROUND(AVG(od.unit_price), 2) AS avg_item_price,
    ROUND(AVG(o.total), 2) AS avg_order_total
FROM Orders o
JOIN OrderDetails od ON o.order_id = od.order_id
WHERE o.status = 'completed'
GROUP BY pricing_period
ORDER BY revenue DESC;

COMMENT ON VIEW v_lunch_vs_dinner_analysis IS 'Compares lunch special pricing vs regular pricing. Shows revenue impact of discounted lunch hours.';

-- ============================================================
-- ANALYTICS VIEW 7: v_kitchen_efficiency
-- Kitchen performance metrics
--
-- Business Use: Kitchen staffing, prep time optimization
-- ============================================================
CREATE OR REPLACE VIEW v_kitchen_efficiency AS
WITH order_prep AS (
    SELECT
        o.order_id,
        o.order_time,
        o.status,
        o.employee_id,
        e.full_name AS staff_name,
        e.role,
        SUM(m.estimated_prep_minutes * od.quantity) AS total_prep_minutes,
        COUNT(DISTINCT od.menu_id) AS unique_dishes
    FROM Orders o
    JOIN Employees e ON o.employee_id = e.employee_id
    JOIN OrderDetails od ON o.order_id = od.order_id
    JOIN Menus m ON od.menu_id = m.menu_id
    WHERE o.status IN ('preparing', 'ready', 'completed')
    GROUP BY o.order_id, o.order_time, o.status, o.employee_id, e.full_name, e.role
)
SELECT
    staff_name,
    role,
    COUNT(*) AS orders_handled,
    SUM(total_prep_minutes) AS total_prep_minutes,
    ROUND(AVG(total_prep_minutes), 2) AS avg_prep_minutes,
    SUM(unique_dishes) AS total_dishes_prepared
FROM order_prep
GROUP BY staff_name, role, employee_id
ORDER BY orders_handled DESC;

COMMENT ON VIEW v_kitchen_efficiency IS 'Kitchen staff performance: orders handled, prep time, dishes prepared. Used for staffing optimization.';

-- ============================================================
-- ANALYTICS VIEW 8: v_vat_breakdown_monthly
-- Monthly VAT summary for Czech tax reporting
--
-- Business Use: Tax filing, accountant reporting
-- ============================================================
CREATE OR REPLACE VIEW v_vat_breakdown_monthly AS
SELECT
    DATE_TRUNC('month', order_time)::DATE AS month,
    SUM(subtotal) AS total_subtotal,
    SUM(vat_amount) AS total_vat_12pct,
    ROUND(SUM(vat_amount) / NULLIF(SUM(subtotal), 0) * 100, 2) AS effective_vat_rate,
    SUM(total) AS gross_revenue,
    SUM(CASE WHEN order_type = 'dine_in' THEN total ELSE 0 END) AS dine_in,
    SUM(CASE WHEN order_type = 'delivery' THEN total ELSE 0 END) AS delivery,
    SUM(CASE WHEN order_type = 'event' THEN total ELSE 0 END) AS events,
    SUM(CASE WHEN order_type = 'takeaway' THEN total ELSE 0 END) AS takeaway
FROM Orders
WHERE status = 'completed'
GROUP BY DATE_TRUNC('month', order_time)
ORDER BY month;

COMMENT ON VIEW v_vat_breakdown_monthly IS 'Monthly VAT breakdown by revenue category. Essential for Czech tax filing (12% reduced rate for restaurant services).';

-- ============================================================
-- ANALYTICS VIEW 9: v_customer_behavior
-- Customer behavior patterns
--
-- Business Use: Marketing segmentation, personalization
-- ============================================================
CREATE OR REPLACE VIEW v_customer_behavior AS
WITH customer_stats AS (
    SELECT
        u.user_id,
        u.full_name,
        u.role,
        COUNT(o.order_id) AS total_orders,
        SUM(o.total) AS lifetime_value,
        AVG(o.total) AS avg_order_value,
        MAX(o.order_time) AS last_order,
        MIN(o.order_time) AS first_order,
        -- Order type preferences
        COUNT(o.order_id) FILTER (WHERE o.order_type = 'dine_in') AS dine_in_count,
        COUNT(o.order_id) FILTER (WHERE o.order_type = 'delivery') AS delivery_count,
        COUNT(o.order_id) FILTER (WHERE o.order_type = 'event') AS event_count,
        -- Source preferences
        COUNT(o.order_id) FILTER (WHERE o.source = 'wolt') AS wolt_count,
        COUNT(o.order_id) FILTER (WHERE o.source = 'bolt') AS bolt_count,
        COUNT(o.order_id) FILTER (WHERE o.source = 'walk-in') AS walkin_count,
        -- Time preferences
        MODE() WITHIN GROUP (ORDER BY EXTRACT(HOUR FROM o.order_time)) AS preferred_hour,
        MODE() WITHIN GROUP (ORDER BY EXTRACT(DOW FROM o.order_time)) AS preferred_day
    FROM Users u
    LEFT JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    WHERE u.role IN ('customer', 'vip')   -- 'vip' is a customer tier, not a separate audience
    GROUP BY u.user_id, u.full_name, u.role
)
SELECT * FROM customer_stats
ORDER BY lifetime_value DESC NULLS LAST;

COMMENT ON VIEW v_customer_behavior IS 'Customer behavior analysis: preferences for order type, source, time of day. Used for targeted marketing.';

-- ============================================================
-- ANALYTICS VIEW 10: v_revenue_forecast
-- Simple revenue forecast using moving average
--
-- Business Use: Financial planning, cash flow prediction
-- ============================================================
CREATE OR REPLACE VIEW v_revenue_forecast AS
WITH daily AS (
    SELECT
        DATE(order_time) AS day,
        SUM(total) AS revenue
    FROM Orders
    WHERE status = 'completed'
    GROUP BY DATE(order_time)
)
SELECT
    day,
    revenue AS actual_revenue,
    -- 7-day moving average
    ROUND(AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma_7d,
    -- 30-day moving average
    ROUND(AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 29 PRECEDING AND CURRENT ROW), 2) AS ma_30d,
    -- Day of week pattern (same day last week)
    LAG(revenue, 7) OVER (ORDER BY day) AS same_day_last_week
FROM daily
ORDER BY day;

COMMENT ON VIEW v_revenue_forecast IS 'Revenue forecasting using moving averages. 7-day MA for short-term, 30-day MA for trend. Same-day-last-week for seasonality.';

-- ============================================================
-- ANALYTICS VIEW 11: v_top_customers
-- Ranked customer list by multiple metrics
-- ============================================================
CREATE OR REPLACE VIEW v_top_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY lifetime_value DESC) AS revenue_rank,
    ROW_NUMBER() OVER (ORDER BY total_orders DESC) AS frequency_rank,
    user_id,
    full_name,
    email,
    total_orders,
    lifetime_value,
    avg_order_value,
    -- v_customer_order_history exposes this as last_order_time (not last_order);
    -- aliased back so downstream consumers keep the short name.
    last_order_time AS last_order,
    loyalty_points,
    CASE
        WHEN lifetime_value > 1000 THEN 'Platinum'
        WHEN lifetime_value > 500 THEN 'Gold'
        WHEN lifetime_value > 200 THEN 'Silver'
        ELSE 'Bronze'
    END AS tier
FROM v_customer_order_history
ORDER BY lifetime_value DESC;

COMMENT ON VIEW v_top_customers IS 'Ranked customer list by revenue and frequency. Includes loyalty tier classification.';

-- ============================================================
-- ANALYTICS VIEWS REGISTERED
-- ============================================================
-- View Name                  | Category           | Key SQL Patterns
-- --------------------------|--------------------|---------------------------
-- v_customer_rfm            | Customer Analytics | CTE, NTILE, CASE, window
-- v_cohort_retention        | Customer Analytics | CTE, DATE_TRUNC, AGE
-- v_monthly_revenue_trends  | Financial          | LAG, AVG OVER, SUM OVER
-- v_hourly_demand_patterns  | Operations         | EXTRACT, GROUPING SETS
-- v_source_performance      | Marketing          | CASE, estimation logic
-- v_lunch_vs_dinner_analysis| Pricing            | CASE, conditional agg
-- v_kitchen_efficiency      | Operations         | SUM OVER, MODE()
-- v_vat_breakdown_monthly   | Finance            | DATE_TRUNC, FILTER
-- v_customer_behavior       | Customer Analytics | MODE(), preference counts
-- v_revenue_forecast        | Financial          | Moving averages, LAG
-- v_top_customers           | CRM                | ROW_NUMBER, tiering
--
-- Total: 11 advanced analytics views
-- SQL Patterns: CTEs, window functions (LAG, LEAD, NTILE, ROW_NUMBER, AVG OVER),
--               DATE_TRUNC, FILTER clause, CASE expressions, MODE()
-- ============================================================
