-- ============================================================
-- Golden Dragon Prague - Advanced Analytics Queries
--
-- These queries demonstrate advanced SQL techniques:
-- - Window functions (LAG, LEAD, ROW_NUMBER, NTILE, RANK)
-- - Common Table Expressions (CTEs)
-- - ROLLUP / CUBE for multi-dimensional analysis
-- - FILTER clause for conditional aggregation
-- - JSONB path queries
-- - Date/time manipulation
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/09_analytics_queries.sql
-- ============================================================

-- ============================================================
-- QUERY 1: RFM Customer Segmentation with Detailed Analysis
-- ============================================================
SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(AVG(recency_days), 1) AS avg_recency_days,
    ROUND(AVG(frequency), 1) AS avg_frequency,
    ROUND(AVG(monetary), 2) AS avg_ltv,
    ROUND(SUM(monetary), 2) AS segment_total_value
FROM v_customer_rfm
GROUP BY segment
ORDER BY segment_total_value DESC;

-- ============================================================
-- QUERY 2: Customer Cohort Retention Matrix
-- ============================================================
SELECT
    cohort_month,
    months_since_first,
    retention_pct
FROM v_cohort_retention
ORDER BY cohort_month, months_since_first;

-- ============================================================
-- QUERY 3: Monthly Revenue Trends with Forecasting
-- ============================================================
SELECT
    month,
    orders_count,
    revenue,
    mom_growth_pct,
    rolling_3mo_avg,
    cumulative_revenue
FROM v_monthly_revenue_trends
ORDER BY month;

-- ============================================================
-- QUERY 4: Hourly Demand Heatmap Data
-- ============================================================
SELECT
    weekday_name,
    hour_of_day,
    order_count,
    revenue,
    ROUND(revenue / NULLIF(order_count, 0), 2) AS avg_order_value
FROM v_hourly_demand_patterns
ORDER BY day_of_week, hour_of_day;

-- ============================================================
-- QUERY 5: Channel Performance Comparison
-- ============================================================
SELECT
    source,
    order_type,
    orders,
    gross_revenue,
    estimated_platform_fees,
    estimated_net_revenue,
    ROUND(estimated_net_revenue / NULLIF(orders, 0), 2) AS avg_net_per_order
FROM v_source_performance
ORDER BY estimated_net_revenue DESC;

-- ============================================================
-- QUERY 6: Revenue Contribution by Menu Category (ROLLUP)
--
-- Two things this query gets wrong if written the obvious way:
--
--  1. GROUP BY ROLLUP(c.category_id, c.name_en) is a rollup over two columns
--     that determine each other, so it emits each category TWICE - once as
--     (id, name) and once as (id, NULL) - plus the grand total.
--     ROLLUP((c.category_id, c.name_en)) treats the pair as ONE level, which is
--     what "subtotal per category" actually means.
--
--  2. SUM(SUM(...)) OVER () as the denominator sums the grand-total row on top
--     of the detail rows, so every percentage came out halved (and with the
--     duplicate rows above, quartered). The denominator has to come from the
--     detail grain only - here, a scalar subquery over the same CTE.
-- ============================================================
WITH category_revenue AS (
    SELECT
        c.category_id,
        c.name_en                        AS category,
        COUNT(od.order_detail_id)        AS items_sold,
        SUM(od.quantity)                 AS portions,
        SUM(od.quantity * od.unit_price) AS revenue
    FROM OrderDetails od
    JOIN Menus m ON od.menu_id = m.menu_id
    JOIN MenuCategories c ON m.category_id = c.category_id
    JOIN Orders o ON od.order_id = o.order_id AND o.status = 'completed'
    GROUP BY c.category_id, c.name_en
)
SELECT
    COALESCE(category, 'TOTAL') AS category,
    SUM(items_sold)             AS items_sold,
    SUM(portions)               AS portions,
    SUM(revenue)                AS revenue,
    ROUND(
        SUM(revenue) / NULLIF((SELECT SUM(revenue) FROM category_revenue), 0) * 100,
        2
    ) AS pct_of_total
FROM category_revenue
GROUP BY ROLLUP((category_id, category))
ORDER BY GROUPING(category_id), category;   -- TOTAL last, not sorted alphabetically

-- ============================================================
-- QUERY 7: Advanced JSONB Query - Extract all dietary restrictions
--
-- The filter was `special_requests ->> 'diet' IS NOT NULL`, which contradicts
-- both the title and the six allergy columns this query selects: it threw away
-- every order that declared an allergy but no diet. No seed order carries a
-- 'diet' key, so the query returned zero rows on every run - an empty result
-- from a kitchen-facing query reads as "no restrictions to worry about".
--
-- `?|` matches an order carrying EITHER key, and unlike `->> ... IS NOT NULL`
-- it is a GIN-indexable operator, so idx_special_requests_gin can serve it.
-- ============================================================
SELECT
    order_id,
    COALESCE(u.full_name, 'Walk-in / Unknown') AS full_name,
    o.order_time,
    -- Extract specific JSONB fields
    o.special_requests ->> 'diet' AS diet,
    o.special_requests ->> 'spicy' AS spice_pref,
    o.special_requests ->> 'notes' AS notes,
    -- Extract array elements
    (o.special_requests -> 'allergies')::TEXT AS allergies_array,
    -- Check if specific key exists
    (o.special_requests ? 'allergies') AS has_allergy_note,
    -- JSONB path query (PostgreSQL 12+)
    jsonb_path_query_array(o.special_requests, '$.allergies[*]') AS allergies_list
FROM Orders o
-- LEFT JOIN: a walk-in order has no user_id, and its allergy note matters just
-- as much as a registered customer's.
LEFT JOIN Users u ON o.user_id = u.user_id
WHERE o.special_requests ?| ARRAY['diet', 'allergies']
ORDER BY o.order_time DESC;

-- ============================================================
-- QUERY 8: Window Function - Running Total of Daily Revenue
-- ============================================================
WITH daily AS (
    SELECT
        DATE(order_time) AS day,
        SUM(total) AS daily_revenue
    FROM Orders
    WHERE status = 'completed'
    GROUP BY DATE(order_time)
)
SELECT
    day,
    daily_revenue,
    -- Running total
    SUM(daily_revenue) OVER (ORDER BY day ROWS UNBOUNDED PRECEDING) AS running_total,
    -- Previous day comparison
    LAG(daily_revenue, 1) OVER (ORDER BY day) AS prev_day_revenue,
    -- Next day (for context)
    LEAD(daily_revenue, 1) OVER (ORDER BY day) AS next_day_revenue,
    -- Day-over-day change
    ROUND(
        (daily_revenue - LAG(daily_revenue, 1) OVER (ORDER BY day)) /
        NULLIF(LAG(daily_revenue, 1) OVER (ORDER BY day), 0) * 100,
        2
    ) AS dod_change_pct
FROM daily
ORDER BY day;

-- ============================================================
-- QUERY 9: Top N Dishes with Running Percentage
-- ============================================================
WITH dish_sales AS (
    SELECT
        m.name_en,
        m.category_id,
        c.name_en AS category,
        SUM(od.quantity) AS portions_sold,
        SUM(od.quantity * od.unit_price) AS revenue
    FROM OrderDetails od
    JOIN Menus m ON od.menu_id = m.menu_id
    JOIN MenuCategories c ON m.category_id = c.category_id
    JOIN Orders o ON od.order_id = o.order_id AND o.status = 'completed'
    GROUP BY m.menu_id, m.name_en, m.category_id, c.name_en
)
SELECT
    name_en,
    category,
    portions_sold,
    revenue,
    -- Rank within category
    RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS category_rank,
    -- Running percentage of total
    ROUND(
        revenue / SUM(revenue) OVER () * 100,
        2
    ) AS pct_of_total_revenue,
    -- Cumulative percentage
    ROUND(
        SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) /
        SUM(revenue) OVER () * 100,
        2
    ) AS cumulative_pct
FROM dish_sales
ORDER BY revenue DESC;

-- ============================================================
-- QUERY 10: Customer Purchase Frequency Analysis (NTILE)
-- ============================================================
WITH customer_freq AS (
    SELECT
        u.user_id,
        u.full_name,
        COUNT(o.order_id) AS order_count,
        -- COALESCE, not a bare SUM: the LEFT JOIN yields NULL for a customer who
        -- has never completed an order, and in an ASC sort Postgres puts NULLs
        -- LAST - so the one person who has spent nothing was ranked above
        -- everyone who has, landing in value_tier 4 and getting labelled
        -- 'BIG SPENDER'. A customer who has spent nothing has spent 0.
        COALESCE(SUM(o.total), 0) AS lifetime_value
    FROM Users u
    LEFT JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    WHERE u.role IN ('customer', 'vip')   -- 'vip' is a customer tier, not a separate audience
    GROUP BY u.user_id, u.full_name
),
-- NTILE numbers the tiles in the sort order given: with ORDER BY ... DESC the
-- BEST customers land in tile 1 and the worst in tile 4, so testing `tier >= 3`
-- labelled the bottom half 'HIGH VALUE' and the top half 'STANDARD' - exactly
-- inverted. Sorting ascending makes tier 4 the top quartile, which is how the
-- labels below (and every other tiering in this project) read it.
tiered AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY order_count)    AS frequency_tier,  -- 4 = most orders
        NTILE(4) OVER (ORDER BY lifetime_value) AS value_tier       -- 4 = highest spend
    FROM customer_freq
)
SELECT
    user_id,
    full_name,
    order_count,
    lifetime_value,
    frequency_tier,
    value_tier,
    CASE
        WHEN frequency_tier >= 3 AND value_tier >= 3 THEN 'HIGH VALUE'
        WHEN frequency_tier >= 3                     THEN 'FREQUENT'
        WHEN value_tier     >= 3                     THEN 'BIG SPENDER'
        ELSE 'STANDARD'
    END AS customer_class
FROM tiered
ORDER BY lifetime_value DESC;

-- ============================================================
-- QUERY 11: Recursive CTE - Order Cascade Analysis
-- Find customers who ordered multiple times and their patterns
-- ============================================================
WITH RECURSIVE customer_orders AS (
    -- Anchor: first order per customer
    SELECT
        u.user_id,
        u.full_name,
        o.order_id,
        o.order_time,
        o.total,
        1 AS order_number
    FROM Users u
    JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    WHERE o.order_time = (
        SELECT MIN(o2.order_time)
        FROM Orders o2
        WHERE o2.user_id = u.user_id AND o2.status = 'completed'
    )
    UNION ALL
    -- Recursive: subsequent orders
    SELECT
        co.user_id,
        co.full_name,
        o.order_id,
        o.order_time,
        o.total,
        co.order_number + 1
    FROM customer_orders co
    JOIN Orders o ON co.user_id = o.user_id AND o.status = 'completed'
    WHERE o.order_time > co.order_time
      AND NOT EXISTS (
          SELECT 1 FROM Orders o2
          WHERE o2.user_id = co.user_id
            AND o2.status = 'completed'
            AND o2.order_time > co.order_time
            AND o2.order_time < o.order_time
      )
)
SELECT
    full_name,
    COUNT(*) AS total_orders,
    SUM(total) AS total_spent,
    AVG(total) AS avg_order,
    MIN(order_time) AS first_order,
    MAX(order_time) AS last_order,
    MAX(order_number) AS order_sequence
FROM customer_orders
GROUP BY user_id, full_name
HAVING COUNT(*) > 1
ORDER BY total_spent DESC;

-- ============================================================
-- QUERY 12: Cross-tabulation (PIVOT-like) - Orders by Type and Source
-- ============================================================
SELECT
    source,
    COUNT(*) FILTER (WHERE order_type = 'dine_in') AS dine_in,
    COUNT(*) FILTER (WHERE order_type = 'delivery') AS delivery,
    COUNT(*) FILTER (WHERE order_type = 'takeaway') AS takeaway,
    COUNT(*) FILTER (WHERE order_type = 'event') AS event,
    COUNT(*) AS total,
    ROUND(AVG(total), 2) AS avg_order_value
FROM Orders
WHERE status = 'completed'
GROUP BY source
ORDER BY total DESC;

-- ============================================================
-- QUERY 13: Advanced JSONB - Query nested dietary preferences
-- ============================================================
SELECT
    order_id,
    u.full_name,
    -- Check if JSONB contains specific key-value
    CASE WHEN special_requests @> '{"diet": "vegetarian"}' THEN 'Vegetarian' ELSE '' END AS is_vegetarian,
    CASE WHEN special_requests @> '{"diet": "vegan"}' THEN 'Vegan' ELSE '' END AS is_vegan,
    -- Check if array contains element
    CASE WHEN special_requests -> 'allergies' ? 'peanuts' THEN 'PEANUT ALLERGY' ELSE '' END AS peanut_warning,
    special_requests ->> 'spicy' AS spice_level,
    special_requests ->> 'notes' AS notes
FROM Orders o
JOIN Users u ON o.user_id = u.user_id
WHERE special_requests IS NOT NULL
  AND (
    special_requests @> '{"diet": "vegetarian"}'
    OR special_requests @> '{"diet": "vegan"}'
    OR special_requests -> 'allergies' ? 'peanuts'
  )
ORDER BY order_id;

-- ============================================================
-- QUERY 14: Data Quality Check - Find Anomalies
-- ============================================================
-- Orders with missing customer
SELECT 'Orphan orders (no user)' AS anomaly, COUNT(*) AS count
FROM Orders o
LEFT JOIN Users u ON o.user_id = u.user_id
WHERE u.user_id IS NULL

UNION ALL

-- Orders with missing items
SELECT 'Orders with no items', COUNT(*)
FROM Orders o
LEFT JOIN OrderDetails od ON o.order_id = od.order_id
WHERE od.order_detail_id IS NULL
  AND o.status NOT IN ('cancelled')

UNION ALL

-- Negative inventory
SELECT 'Negative inventory items', COUNT(*)
FROM Inventory
WHERE quantity < 0

UNION ALL

-- Completed orders with zero total
SELECT 'Completed orders with zero total', COUNT(*)
FROM Orders
WHERE status = 'completed' AND (total IS NULL OR total = 0)

UNION ALL

-- Orders with invalid status transitions
SELECT 'Orders with status but no time', COUNT(*)
FROM Orders
WHERE status IS NOT NULL AND order_time IS NULL;

-- ============================================================
-- QUERY 15: Performance Test - Explain Plan Analysis
-- ============================================================
-- Run these EXPLAIN ANALYZE queries to verify index usage:
-- (They won't return data, just query plans)

-- Should use idx_orders_status index
-- EXPLAIN ANALYZE SELECT * FROM Orders WHERE status = 'completed';

-- Should use idx_special_requests_gin (GIN index)
-- EXPLAIN ANALYZE SELECT * FROM Orders WHERE special_requests @> '{"diet":"vegetarian"}';

-- Should use idx_orders_date_status (order_time is its leading column)
-- EXPLAIN ANALYZE SELECT * FROM Orders WHERE order_time BETWEEN '2025-01-01' AND '2025-12-31';

-- Should use idx_orderdetails_order + idx_menus_category
-- EXPLAIN ANALYZE SELECT m.name_en, SUM(od.quantity) FROM OrderDetails od
--   JOIN Menus m ON od.menu_id = m.menu_id GROUP BY m.name_en;

-- ============================================================
-- QUERY 16: Advanced - Pareto Analysis (80/20 Rule)
-- Which 20% of customers generate 80% of revenue?
-- ============================================================
WITH customer_revenue AS (
    SELECT
        u.user_id,
        u.full_name,
        SUM(o.total) AS revenue
    FROM Users u
    JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    GROUP BY u.user_id, u.full_name
),
ranked AS (
    SELECT
        *,
        SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) AS cumulative_revenue,
        ROUND(
            SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) /
            SUM(revenue) OVER () * 100,
            2
        ) AS cumulative_pct,
        ROUND(
            ROW_NUMBER() OVER (ORDER BY revenue DESC)::NUMERIC /
            COUNT(*) OVER () * 100,
            2
        ) AS customer_pct
    FROM customer_revenue
)
SELECT
    customer_pct,
    cumulative_pct,
    COUNT(*) AS customers,
    ROUND(SUM(revenue), 2) AS revenue
FROM ranked
GROUP BY customer_pct, cumulative_pct
ORDER BY customer_pct;

-- Find the exact 80/20 threshold
-- NOTE: CTEs do not survive past the semicolon of the statement that declares
-- them, so `ranked` has to be re-declared here rather than reused.
WITH customer_revenue AS (
    SELECT
        u.user_id,
        u.full_name,
        SUM(o.total) AS revenue
    FROM Users u
    JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    GROUP BY u.user_id, u.full_name
),
ranked AS (
    SELECT
        *,
        ROUND(
            SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) /
            SUM(revenue) OVER () * 100,
            2
        ) AS cumulative_pct,
        ROUND(
            ROW_NUMBER() OVER (ORDER BY revenue DESC)::NUMERIC /
            COUNT(*) OVER () * 100,
            2
        ) AS customer_pct
    FROM customer_revenue
)
SELECT
    full_name,
    revenue,
    cumulative_pct,
    customer_pct
FROM ranked
WHERE cumulative_pct >= 78 AND cumulative_pct <= 82
ORDER BY cumulative_pct
LIMIT 5;

-- ============================================================
-- QUERY 17: Multi-dimensional Analysis - Revenue by Month, Type, and Source
--
-- Same denominator trap as Query 6, one dimension deeper. A window SUM over a
-- ROLLUP result set adds the (month), (month, type) and grand-total rows to the
-- detail rows, so `SUM(SUM(total)) OVER (PARTITION BY month)` returned roughly
-- three times each month's real revenue and every percentage came out at about
-- a third of the truth. Aggregating the detail grain in a CTE first gives an
-- honest denominator per month, and GROUPING() picks the right one for the
-- rows where the month itself has been rolled up.
-- ============================================================
WITH base AS (
    SELECT
        TO_CHAR(order_time, 'YYYY-MM') AS month,
        order_type,
        source,
        COUNT(*)   AS orders,
        SUM(total) AS revenue
    FROM Orders
    WHERE status = 'completed'
    GROUP BY 1, 2, 3
),
monthly_totals AS (
    SELECT month, SUM(revenue) AS month_revenue
    FROM base
    GROUP BY month
)
SELECT
    COALESCE(b.month,      'ALL MONTHS') AS month,
    COALESCE(b.order_type, 'ALL TYPES')  AS order_type,
    COALESCE(b.source,     'ALL SOURCES') AS source,
    SUM(b.orders)  AS orders,
    SUM(b.revenue) AS revenue,
    -- Revenue-weighted, unlike AVG() over pre-aggregated rows
    ROUND(SUM(b.revenue) / NULLIF(SUM(b.orders), 0), 2) AS avg_order_value,
    ROUND(
        SUM(b.revenue) / NULLIF(
            CASE WHEN GROUPING(b.month) = 0
                 -- inside one month: month_revenue is constant, MAX just picks it
                 THEN MAX(mt.month_revenue)
                 -- month rolled up: compare against all-time revenue
                 ELSE (SELECT SUM(month_revenue) FROM monthly_totals)
            END, 0) * 100,
        2
    ) AS pct_of_monthly_revenue
FROM base b
JOIN monthly_totals mt ON mt.month = b.month
GROUP BY ROLLUP(b.month, b.order_type, b.source)
ORDER BY GROUPING(b.month), b.month,
         GROUPING(b.order_type), b.order_type,
         GROUPING(b.source), b.source;

-- ============================================================
-- QUERY 18: Advanced CTE - Customer Journey Analysis
-- ============================================================
WITH customer_journey AS (
    SELECT
        u.user_id,
        u.full_name,
        -- First interaction
        MIN(o.order_time) AS first_order_date,
        -- Most recent
        MAX(o.order_time) AS last_order_date,
        -- Total orders
        COUNT(o.order_id) AS total_orders,
        -- Total spent
        SUM(o.total) AS total_spent,
        -- Has this customer ever ordered in the lunch window?
        -- Window rule comes from is_lunch_window(), never re-derived inline.
        BOOL_OR(is_lunch_window(o.order_time)) AS ordered_in_lunch_window,
        -- Preferred channel
        MODE() WITHIN GROUP (ORDER BY o.source) AS preferred_source,
        -- Days between first and last order
        EXTRACT(EPOCH FROM (MAX(o.order_time) - MIN(o.order_time))) / 86400 AS customer_lifespan_days
    FROM Users u
    JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    GROUP BY u.user_id, u.full_name
)
SELECT
    full_name,
    first_order_date,
    last_order_date,
    total_orders,
    total_spent,
    ROUND(total_spent / NULLIF(total_orders, 0), 2) AS avg_order,
    customer_lifespan_days,
    ROUND(total_spent / NULLIF(customer_lifespan_days, 0), 2) AS revenue_per_day,
    ordered_in_lunch_window,
    preferred_source,
    CASE
        WHEN total_orders = 1 THEN 'One-time'
        WHEN total_orders BETWEEN 2 AND 5 THEN 'Occasional'
        WHEN total_orders BETWEEN 6 AND 10 THEN 'Regular'
        ELSE 'Loyal'
    END AS loyalty_category
FROM customer_journey
ORDER BY total_spent DESC;

-- ============================================================
-- QUERY 19: Index Performance Verification
-- ============================================================
-- Check which indexes are actually used
-- pg_stat_user_indexes exposes relname/indexrelname, not tablename/indexname.
SELECT
    schemaname,
    relname      AS tablename,
    indexrelname AS indexname,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE relname IN ('orders', 'orderdetails', 'users', 'menus', 'inventory', 'reservations')
ORDER BY idx_scan DESC;

-- ============================================================
-- QUERY 20: Table Statistics for Query Planning
-- ============================================================
-- pg_stat_user_tables exposes relname, not tablename.
SELECT
    relname AS tablename,
    pg_size_pretty(pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(relname))) AS total_size,
    n_live_tup AS row_count,
    n_dead_tup AS dead_rows,
    ROUND(n_dead_tup::NUMERIC / NULLIF(n_live_tup, 0) * 100, 2) AS dead_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;
