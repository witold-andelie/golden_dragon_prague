-- ============================================================
-- Golden Dragon Prague - Star Schema for Data Warehouse
--
-- This file creates dimension and fact tables for analytics.
-- It demonstrates data warehouse design patterns relevant to SAP BW/4HANA.
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/etl_star_schema.sql
-- ============================================================

-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- ============================================================
-- DIM 1: dim_date
-- Date dimension for time-series analysis
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_date (
    date_key          DATE PRIMARY KEY,
    day               INT NOT NULL,
    month             INT NOT NULL,
    year              INT NOT NULL,
    quarter           INT NOT NULL,
    day_of_week       INT NOT NULL,
    day_name          VARCHAR(10) NOT NULL,
    month_name        VARCHAR(10) NOT NULL,
    is_weekend        BOOLEAN NOT NULL,
    is_lunch_special  BOOLEAN NOT NULL,  -- Mon-Fri 11:00-14:30
    fiscal_year       INT,
    fiscal_quarter    INT
);

COMMENT ON TABLE dim_date IS 'Date dimension for time-series analysis. Pre-computed attributes for fast filtering.';
COMMENT ON COLUMN dim_date.is_lunch_special IS 'TRUE if weekday (Mon-Fri) - used for lunch menu analysis';

-- ============================================================
-- DIM 2: dim_customer
-- Customer dimension with SCD Type 2 support
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_customer (
    customer_key      SERIAL PRIMARY KEY,
    user_id           INT NOT NULL,
    username          VARCHAR(80),
    full_name         VARCHAR(120),
    email             VARCHAR(120),
    phone             VARCHAR(20),
    role              VARCHAR(20),
    loyalty_tier      VARCHAR(20),
    valid_from        DATE NOT NULL,
    valid_to          DATE DEFAULT '9999-12-31',
    is_current        BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE dim_customer IS 'Customer dimension. Supports slowly changing dimensions (SCD Type 2) for historical tracking.';
COMMENT ON COLUMN dim_customer.is_current IS 'TRUE = current version of this customer record';

-- ============================================================
-- DIM 3: dim_menu_item
-- Menu item dimension
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_menu_item (
    menu_key          SERIAL PRIMARY KEY,
    menu_id           INT NOT NULL,
    name_en           VARCHAR(100),
    name_cz           VARCHAR(100),
    category_name_en  VARCHAR(60),
    category_name_cz  VARCHAR(60),
    price_regular     NUMERIC(8,2),
    price_lunch       NUMERIC(8,2),
    spice_level       SMALLINT,
    estimated_prep    INT,
    allergen_count    INT,
    valid_from        DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to          DATE DEFAULT '9999-12-31',
    is_current        BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE dim_menu_item IS 'Menu item dimension with allergen count and pricing. Supports SCD for price changes.';

-- ============================================================
-- DIM 4: dim_channel
-- Order source/channel dimension
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_channel (
    channel_key       SERIAL PRIMARY KEY,
    source            VARCHAR(30) NOT NULL UNIQUE,
    channel_type      VARCHAR(30),  -- direct, delivery_platform, event
    platform_fee_pct  NUMERIC(4,2) DEFAULT 0,  -- Estimated platform commission
    description       TEXT
);

COMMENT ON TABLE dim_channel IS 'Sales channel dimension: walk-in, phone, Wolt, Bolt, etc. Includes estimated platform fees.';

-- ============================================================
-- DIM 5: dim_employee
-- Employee dimension
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_employee (
    employee_key      SERIAL PRIMARY KEY,
    employee_id       INT NOT NULL,
    full_name         VARCHAR(120),
    role              VARCHAR(30),
    hire_date         DATE,
    is_active         BOOLEAN,
    valid_from        DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to          DATE DEFAULT '9999-12-31',
    is_current        BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE dim_employee IS 'Employee dimension for staff performance analysis.';

-- ============================================================
-- FACT TABLE: fact_orders
-- Grain: one row per order line item
-- ============================================================
CREATE TABLE IF NOT EXISTS fact_orders (
    fact_id           SERIAL PRIMARY KEY,
    date_key           DATE NOT NULL REFERENCES dim_date(date_key),
    -- Nullable: walk-in / phone orders legitimately have no user_id. Making this
    -- NOT NULL plus an inner join in the ETL silently dropped those orders.
    customer_key       INT REFERENCES dim_customer(customer_key),
    menu_key           INT NOT NULL REFERENCES dim_menu_item(menu_key),
    channel_key        INT NOT NULL REFERENCES dim_channel(channel_key),
    employee_key       INT REFERENCES dim_employee(employee_key),
    order_id           INT NOT NULL,
    order_detail_id    INT NOT NULL,
    quantity           INT NOT NULL,
    unit_price         NUMERIC(8,2) NOT NULL,
    -- ---- Additive measures at the line grain --------------------------------
    line_total           NUMERIC(10,2) NOT NULL,
    line_vat_amount      NUMERIC(10,2),
    line_delivery_fee    NUMERIC(10,2) DEFAULT 0,
    line_discount_amount NUMERIC(10,2) DEFAULT 0,
    -- ---- Order-grain reference value: NOT additive --------------------------
    -- Repeated on every line of the order. Never SUM() this; use the allocated
    -- line_* measures, or COUNT(DISTINCT order_id) as a denominator.
    order_total        NUMERIC(10,2),
    order_type         VARCHAR(20),
    order_status       VARCHAR(25),
    order_hour         INT,
    order_dow          INT,
    is_lunch_order     BOOLEAN,
    loaded_at          TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE fact_orders IS 'Order line item fact table. Grain: one row per menu item per order. Order-level money (VAT, delivery fee, discount) is allocated to lines pro-rata by line share of subtotal, so every line_* measure is additive at any grain.';
COMMENT ON COLUMN fact_orders.order_total IS 'Order-grain total, repeated per line. NOT additive - do not SUM.';
COMMENT ON COLUMN fact_orders.line_vat_amount IS 'Order VAT allocated to this line pro-rata by line share of order subtotal. Additive.';
COMMENT ON COLUMN fact_orders.line_delivery_fee IS 'Order delivery fee allocated to this line pro-rata. Additive.';
COMMENT ON COLUMN fact_orders.line_discount_amount IS 'Order discount allocated to this line pro-rata. Additive.';

-- Natural-key uniqueness on the "current" slice of each dimension.
-- Without these, re-running this file inserts a second copy of every dimension
-- row and the fact load fans out against the duplicates.
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_customer_current
    ON dim_customer(user_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_menu_item_current
    ON dim_menu_item(menu_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_employee_current
    ON dim_employee(employee_id) WHERE is_current;

-- Indexes on fact table for OLAP queries
CREATE INDEX IF NOT EXISTS idx_fact_date ON fact_orders(date_key);
CREATE INDEX IF NOT EXISTS idx_fact_customer ON fact_orders(customer_key);
CREATE INDEX IF NOT EXISTS idx_fact_menu ON fact_orders(menu_key);
CREATE INDEX IF NOT EXISTS idx_fact_channel ON fact_orders(channel_key);
CREATE INDEX IF NOT EXISTS idx_fact_order ON fact_orders(order_id);

-- ============================================================
-- ETL CONTROL TABLE
-- Tracks ETL pipeline execution for monitoring
-- ============================================================
CREATE TABLE IF NOT EXISTS etl_control (
    etl_id            SERIAL PRIMARY KEY,
    etl_name          VARCHAR(100) NOT NULL,
    started_at        TIMESTAMP DEFAULT NOW(),
    finished_at       TIMESTAMP,
    status            VARCHAR(20) DEFAULT 'running'
        CHECK (status IN ('running', 'completed', 'failed')),
    rows_processed    INT DEFAULT 0,
    error_message     TEXT
);

COMMENT ON TABLE etl_control IS 'ETL pipeline execution log. Used for monitoring and debugging data loads.';

-- ============================================================
-- DATA QUALITY AUDIT TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS data_quality_audit (
    audit_id          SERIAL PRIMARY KEY,
    check_name        VARCHAR(100) NOT NULL,
    check_time        TIMESTAMP DEFAULT NOW(),
    table_name        VARCHAR(50),
    expected_count    INT,
    actual_count      INT,
    discrepancy       INT,
    status            VARCHAR(20)
        CHECK (status IN ('PASS', 'FAIL', 'WARNING')),
    notes             TEXT
);

COMMENT ON TABLE data_quality_audit IS 'Data quality checks log. Tracks row counts, null checks, referential integrity.';

-- ============================================================
-- DIMENSION POPULATION
-- ============================================================

-- Populate dim_date (generate dates for 2024-2025)
INSERT INTO dim_date (date_key, day, month, year, quarter, day_of_week, day_name, month_name, is_weekend, is_lunch_special, fiscal_year, fiscal_quarter)
SELECT
    d::DATE,
    EXTRACT(DAY FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    EXTRACT(YEAR FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(ISODOW FROM d)::INT,
    TO_CHAR(d, 'FMDay'),
    TO_CHAR(d, 'FMMonth'),
    EXTRACT(ISODOW FROM d) IN (6, 7),
    -- dim_date is day-grain, so this can only mean "is the lunch special offered
    -- on this DAY" (Mon-Fri). The old version ANDed two constant-true comparisons
    -- on literal times, which was dead code. Time-of-day is on fact_orders.
    EXTRACT(ISODOW FROM d) BETWEEN 1 AND 5,
    CASE WHEN EXTRACT(MONTH FROM d) >= 4 THEN EXTRACT(YEAR FROM d)::INT ELSE EXTRACT(YEAR FROM d)::INT - 1 END,
    CASE
        WHEN EXTRACT(MONTH FROM d) IN (4,5,6) THEN 1
        WHEN EXTRACT(MONTH FROM d) IN (7,8,9) THEN 2
        WHEN EXTRACT(MONTH FROM d) IN (10,11,12) THEN 3
        ELSE 4
    END
FROM generate_series('2024-01-01'::DATE, '2026-12-31'::DATE, '1 day'::INTERVAL) d
ON CONFLICT (date_key) DO NOTHING;

-- Populate dim_customer (current state)
INSERT INTO dim_customer (user_id, username, full_name, email, phone, role, loyalty_tier, valid_from)
SELECT
    user_id,
    username,
    full_name,
    email,
    phone,
    role,
    CASE
        WHEN loyalty_points > 500 THEN 'Platinum'
        WHEN loyalty_points > 200 THEN 'Gold'
        WHEN loyalty_points > 100 THEN 'Silver'
        ELSE 'Bronze'
    END,
    CURRENT_DATE
FROM Users
-- 'vip' is a loyalty tier of the customer base, not a separate audience.
-- Excluding it dropped the highest-value customers from the whole warehouse.
WHERE role IN ('customer', 'vip')
ON CONFLICT (user_id) WHERE is_current DO NOTHING;

-- Populate dim_menu_item (current state)
INSERT INTO dim_menu_item (menu_id, name_en, name_cz, category_name_en, category_name_cz, price_regular, price_lunch, spice_level, estimated_prep, allergen_count)
SELECT
    m.menu_id,
    m.name_en,
    m.name_cz,
    c.name_en,
    c.name_cz,
    m.price_regular,
    m.price_lunch,
    m.spice_level,
    m.estimated_prep_minutes,
    COUNT(ma.allergen_id)
FROM Menus m
JOIN MenuCategories c ON m.category_id = c.category_id
LEFT JOIN MenuAllergens ma ON m.menu_id = ma.menu_id
GROUP BY m.menu_id, m.name_en, m.name_cz, c.name_en, c.name_cz, m.price_regular, m.price_lunch, m.spice_level, m.estimated_prep_minutes
ON CONFLICT (menu_id) WHERE is_current DO NOTHING;

-- Populate dim_channel
INSERT INTO dim_channel (source, channel_type, platform_fee_pct, description)
VALUES
('walk-in',     'direct',           0,   'In-person walk-in customer'),
('phone',       'direct',           0,   'Phone order'),
('website',     'direct',           0,   'Online ordering via restaurant website'),
('wolt',        'delivery_platform',22,  'Wolt delivery platform (~22% commission)'),
('bolt',        'delivery_platform',22,  'Bolt Food delivery platform (~22% commission)'),
('uber_eats',   'delivery_platform',25,  'Uber Eats (not currently used)')
ON CONFLICT (source) DO NOTHING;

-- Populate dim_employee
INSERT INTO dim_employee (employee_id, full_name, role, hire_date, is_active)
SELECT employee_id, full_name, role, hire_date, is_active
FROM Employees
ON CONFLICT (employee_id) WHERE is_current DO NOTHING;

-- ============================================================
-- ETL STORED PROCEDURES
-- ============================================================

-- ============================================================
-- PROCEDURE 1: sp_load_fact_orders
-- ETL: Extract from operational DB, Transform, Load into fact table
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_load_fact_orders()
LANGUAGE plpgsql AS $$
DECLARE
    v_etl_id INT;
    v_rows_loaded INT := 0;
    v_rows_expected INT := 0;
BEGIN
    -- Log ETL start
    INSERT INTO etl_control (etl_name, status)
    VALUES ('load_fact_orders', 'running')
    RETURNING etl_id INTO v_etl_id;

    -- Full reload. The extract below has no date predicate, so it always
    -- re-reads every order; deleting only rows whose loaded_at >= CURRENT_DATE
    -- left yesterday's rows in place and duplicated the entire history on the
    -- second run of the day.
    DELETE FROM fact_orders;

    -- Extract + Transform + Load
    INSERT INTO fact_orders (
        date_key, customer_key, menu_key, channel_key, employee_key,
        order_id, order_detail_id, quantity, unit_price, line_total,
        line_vat_amount, line_delivery_fee, line_discount_amount,
        order_total, order_type, order_status, order_hour, order_dow, is_lunch_order
    )
    SELECT
        DATE(o.order_time),
        dc.customer_key,
        dm.menu_key,
        dch.channel_key,
        de.employee_key,
        od.order_id,
        od.order_detail_id,
        od.quantity,
        od.unit_price,
        od.quantity * od.unit_price,
        -- Order-level money allocated pro-rata to this line. The weights across
        -- an order sum to 1, so SUM(line_vat_amount) reproduces the order VAT
        -- exactly instead of multiplying it by the number of line items.
        ROUND(o.vat_amount      * alloc.w, 2),
        ROUND(COALESCE(o.delivery_fee, 0)    * alloc.w, 2),
        ROUND(COALESCE(o.discount_amount, 0) * alloc.w, 2),
        o.total,
        o.order_type,
        o.status,
        EXTRACT(HOUR FROM o.order_time)::INT,
        EXTRACT(ISODOW FROM o.order_time)::INT,
        CASE
            WHEN EXTRACT(HOUR FROM o.order_time) BETWEEN 11 AND 14
                 AND EXTRACT(ISODOW FROM o.order_time) BETWEEN 1 AND 5
            THEN TRUE ELSE FALSE
        END
    FROM OrderDetails od
    JOIN Orders o ON od.order_id = o.order_id
    -- LEFT JOIN: walk-in orders have no user_id and must not be dropped.
    LEFT JOIN dim_customer dc ON o.user_id = dc.user_id AND dc.is_current
    JOIN dim_menu_item dm ON od.menu_id = dm.menu_id AND dm.is_current
    JOIN dim_channel dch ON o.source = dch.source
    LEFT JOIN dim_employee de ON o.employee_id = de.employee_id AND de.is_current
    LEFT JOIN LATERAL (
        SELECT COALESCE((od.quantity * od.unit_price) / NULLIF(o.subtotal, 0), 0) AS w
    ) alloc ON TRUE;

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

    -- Guard against silent row loss: the inner joins above (menu, channel) can
    -- still drop lines if a dimension is incomplete. Record it rather than
    -- letting the fact table quietly disagree with the source.
    SELECT COUNT(*) INTO v_rows_expected FROM OrderDetails;

    INSERT INTO data_quality_audit (
        check_name, table_name, expected_count, actual_count, discrepancy, status, notes
    )
    VALUES (
        'fact_orders_row_completeness',
        'fact_orders',
        v_rows_expected,
        v_rows_loaded,
        v_rows_expected - v_rows_loaded,
        CASE WHEN v_rows_expected = v_rows_loaded THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN v_rows_expected = v_rows_loaded
             THEN 'All order lines loaded'
             ELSE (v_rows_expected - v_rows_loaded) || ' order lines dropped by dimension joins'
        END
    );

    -- Update ETL log
    UPDATE etl_control
    SET finished_at = NOW(),
        status = 'completed',
        rows_processed = v_rows_loaded
    WHERE etl_id = v_etl_id;

    RAISE NOTICE 'ETL completed: % rows loaded into fact_orders', v_rows_loaded;
END;
$$;

COMMENT ON PROCEDURE sp_load_fact_orders() IS 'ETL procedure: loads operational order data into star schema fact table. Idempotent - full reload (truncate-and-load), so re-running never duplicates rows.';

-- ============================================================
-- PROCEDURE 2: sp_run_data_quality_checks
-- Validates data integrity across the database
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_run_data_quality_checks()
LANGUAGE plpgsql AS $$
DECLARE
    v_check_name VARCHAR(100);
    v_table_name VARCHAR(50);
    v_expected INT;
    v_actual INT;
    v_discrepancy INT;
    v_status VARCHAR(20);
    v_notes TEXT;
BEGIN
    -- Check 1: All orders have at least one detail item
    v_check_name := 'orders_without_items';
    v_table_name := 'OrderDetails';
    SELECT COUNT(*) INTO v_expected FROM Orders;
    SELECT COUNT(DISTINCT order_id) INTO v_actual FROM OrderDetails;
    v_discrepancy := v_expected - v_actual;
    v_status := CASE WHEN v_discrepancy = 0 THEN 'PASS' ELSE 'FAIL' END;
    v_notes := CASE WHEN v_discrepancy = 0 THEN 'All orders have items' ELSE v_discrepancy || ' orders missing items' END;

    INSERT INTO data_quality_audit (check_name, table_name, expected_count, actual_count, discrepancy, status, notes)
    VALUES (v_check_name, v_table_name, v_expected, v_actual, v_discrepancy, v_status, v_notes);

    -- Check 2: No negative inventory
    v_check_name := 'negative_inventory';
    v_table_name := 'Inventory';
    SELECT COUNT(*) INTO v_actual FROM Inventory WHERE quantity < 0;
    v_status := CASE WHEN v_actual = 0 THEN 'PASS' ELSE 'FAIL' END;
    v_notes := CASE WHEN v_actual = 0 THEN 'No negative inventory' ELSE v_actual || ' items with negative stock' END;

    INSERT INTO data_quality_audit (check_name, table_name, expected_count, actual_count, discrepancy, status, notes)
    VALUES (v_check_name, v_table_name, 0, v_actual, v_actual, v_status, v_notes);

    -- Check 3: All order details reference valid menu
    v_check_name := 'orphan_order_details';
    v_table_name := 'OrderDetails';
    SELECT COUNT(*) INTO v_actual
    FROM OrderDetails od
    LEFT JOIN Menus m ON od.menu_id = m.menu_id
    WHERE m.menu_id IS NULL;
    v_status := CASE WHEN v_actual = 0 THEN 'PASS' ELSE 'FAIL' END;
    v_notes := CASE WHEN v_actual = 0 THEN 'No orphan order details' ELSE v_actual || ' orphan order details' END;

    INSERT INTO data_quality_audit (check_name, table_name, expected_count, actual_count, discrepancy, status, notes)
    VALUES (v_check_name, v_table_name, 0, v_actual, v_actual, v_status, v_notes);

    -- Check 4: Order totals match sum of details
    v_check_name := 'order_totals_mismatch';
    v_table_name := 'Orders';
    SELECT COUNT(*) INTO v_actual
    FROM Orders o
    WHERE o.status = 'completed'
      AND ABS(o.total - (SELECT COALESCE(SUM(quantity * unit_price), 0) FROM OrderDetails WHERE order_id = o.order_id)) > 0.01;
    v_status := CASE WHEN v_actual = 0 THEN 'PASS' ELSE 'FAIL' END;
    v_notes := CASE WHEN v_actual = 0 THEN 'All order totals correct' ELSE v_actual || ' orders with total mismatch' END;

    INSERT INTO data_quality_audit (check_name, table_name, expected_count, actual_count, discrepancy, status, notes)
    VALUES (v_check_name, v_table_name, 0, v_actual, v_actual, v_status, v_notes);

    -- Check 5: Completed orders have payments (or are cash)
    v_check_name := 'completed_orders_without_payment';
    v_table_name := 'Payments';
    SELECT COUNT(*) INTO v_actual
    FROM Orders o
    LEFT JOIN Payments p ON o.order_id = p.order_id
    WHERE o.status = 'completed' AND p.payment_id IS NULL;
    v_status := CASE WHEN v_actual = 0 THEN 'PASS' ELSE 'WARNING' END;
    v_notes := CASE WHEN v_actual = 0 THEN 'All completed orders have payments' ELSE v_actual || ' completed orders without payment records' END;

    INSERT INTO data_quality_audit (check_name, table_name, expected_count, actual_count, discrepancy, status, notes)
    VALUES (v_check_name, v_table_name, 0, v_actual, v_actual, v_status, v_notes);

    RAISE NOTICE 'Data quality checks completed';
END;
$$;

COMMENT ON PROCEDURE sp_run_data_quality_checks() IS 'Runs data quality validation checks: orphan records, negative inventory, total mismatches, missing payments.';

-- ============================================================
-- PROCEDURE 3: sp_daily_etl_pipeline
-- Simulates a daily data warehouse ETL job
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_daily_etl_pipeline()
LANGUAGE plpgsql AS $$
BEGIN
    -- Step 1: Run data quality checks
    CALL sp_run_data_quality_checks();

    -- Step 2: Load fact table
    CALL sp_load_fact_orders();

    -- Step 3: Log completion
    INSERT INTO etl_control (etl_name, status, rows_processed)
    VALUES ('daily_etl_pipeline', 'completed', 0);

    RAISE NOTICE 'Daily ETL pipeline completed successfully';
END;
$$;

COMMENT ON PROCEDURE sp_daily_etl_pipeline() IS 'Complete daily ETL: data quality checks + fact table load. Simulates production data warehouse pipeline.';

-- ============================================================
-- ANALYTICAL VIEWS ON STAR SCHEMA
-- ============================================================

-- ============================================================
-- VIEW: v_fact_order_analysis
-- OLAP-style analysis on fact table
-- ============================================================
CREATE OR REPLACE VIEW v_fact_order_analysis AS
SELECT
    dd.year,
    dd.month,
    dd.day_name,
    COALESCE(dc.full_name, 'Walk-in / Unknown') AS customer,
    dm.name_en AS dish,
    dch.source AS channel,
    de.full_name AS staff,
    SUM(fo.quantity) AS portions,
    SUM(fo.line_total) AS revenue,
    COUNT(DISTINCT fo.order_id) AS orders
FROM fact_orders fo
JOIN dim_date dd ON fo.date_key = dd.date_key
-- LEFT JOIN + COALESCE: customer_key is NULL for walk-in orders. An inner join
-- here would hide them from the analysis entirely.
LEFT JOIN dim_customer dc ON fo.customer_key = dc.customer_key
JOIN dim_menu_item dm ON fo.menu_key = dm.menu_key
JOIN dim_channel dch ON fo.channel_key = dch.channel_key
LEFT JOIN dim_employee de ON fo.employee_key = de.employee_key
GROUP BY dd.year, dd.month, dd.day_name, dc.full_name, dm.name_en, dch.source, de.full_name
ORDER BY dd.year, dd.month, revenue DESC;

COMMENT ON VIEW v_fact_order_analysis IS 'OLAP-style multi-dimensional analysis on fact table. Supports slicing by date, customer, menu, channel, employee.';

-- ============================================================
-- VIEW: v_dim_customer_history
-- Slowly changing dimension view (current + historical)
-- ============================================================
CREATE OR REPLACE VIEW v_dim_customer_history AS
SELECT
    customer_key,
    user_id,
    full_name,
    role,
    loyalty_tier,
    valid_from,
    valid_to,
    is_current,
    CASE WHEN is_current THEN 'Current' ELSE 'Historical' END AS record_type
FROM dim_customer
ORDER BY user_id, valid_from;

-- ============================================================
-- MATERIALIZED VIEW: mv_daily_kpi
-- Pre-computed daily KPIs for fast dashboard queries
-- ============================================================
-- Revenue measures are restricted to completed orders (cancelled and in-flight
-- orders are not realised revenue) and use the allocated line_* measures, which
-- are additive at the line grain. The previous version summed order-grain
-- vat_amount and averaged order-grain order_total across line items, inflating
-- both by the number of lines per order.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_kpi AS
SELECT
    dd.date_key,
    dd.day_name,
    COUNT(DISTINCT fo.order_id)                                              AS total_orders,
    COUNT(DISTINCT fo.order_id) FILTER (WHERE fo.order_status = 'completed') AS completed_orders,
    COUNT(DISTINCT fo.customer_key)                                          AS unique_customers,
    -- Net of VAT
    SUM(fo.line_total) FILTER (WHERE fo.order_status = 'completed')          AS net_revenue,
    SUM(fo.line_vat_amount) FILTER (WHERE fo.order_status = 'completed')     AS vat_collected,
    -- What the customer actually paid: net + VAT + delivery - discount
    SUM(fo.line_total + COALESCE(fo.line_vat_amount, 0)
        + COALESCE(fo.line_delivery_fee, 0)
        - COALESCE(fo.line_discount_amount, 0))
        FILTER (WHERE fo.order_status = 'completed')                         AS gross_revenue,
    ROUND(
        SUM(fo.line_total + COALESCE(fo.line_vat_amount, 0)
            + COALESCE(fo.line_delivery_fee, 0)
            - COALESCE(fo.line_discount_amount, 0))
            FILTER (WHERE fo.order_status = 'completed')
        / NULLIF(COUNT(DISTINCT fo.order_id) FILTER (WHERE fo.order_status = 'completed'), 0),
        2
    )                                                                        AS avg_order_value,
    SUM(fo.line_total) FILTER (WHERE fo.order_status = 'completed' AND fo.order_type = 'dine_in')  AS dine_in,
    SUM(fo.line_total) FILTER (WHERE fo.order_status = 'completed' AND fo.order_type = 'delivery') AS delivery,
    SUM(fo.line_total) FILTER (WHERE fo.order_status = 'completed' AND fo.order_type = 'event')    AS event
FROM fact_orders fo
JOIN dim_date dd ON fo.date_key = dd.date_key
GROUP BY dd.date_key, dd.day_name
ORDER BY dd.date_key;

COMMENT ON MATERIALIZED VIEW mv_daily_kpi IS 'Pre-computed daily KPIs for fast dashboard queries. Revenue measures cover completed orders only and use the pro-rata allocated line_* measures. Refresh via REFRESH MATERIALIZED VIEW mv_daily_kpi;';

-- Index on materialized view for fast filtering
CREATE INDEX IF NOT EXISTS idx_mv_daily_kpi_date ON mv_daily_kpi(date_key);

-- ============================================================
-- POPULATE DIM_DATE (if not already done)
-- ============================================================
-- Note: dim_date population is in the main star schema file above

-- ============================================================
-- RUN INITIAL ETL LOAD
-- ============================================================
-- Load existing operational data into fact table
CALL sp_load_fact_orders();

-- Refresh materialized views
REFRESH MATERIALIZED VIEW mv_daily_kpi;

\echo ''
\echo 'Star schema created and populated.'
\echo 'Dimensions: dim_date, dim_customer, dim_menu_item, dim_channel, dim_employee'
\echo 'Fact table:  fact_orders'
\echo 'Run ETL:      CALL sp_daily_etl_pipeline();'
\echo 'Refresh MV:   REFRESH MATERIALIZED VIEW mv_daily_kpi;'
