-- ============================================================
-- Golden Dragon Prague - Business Logic Functions (PL/pgSQL)
--
-- These functions encode the core business rules of the restaurant.
-- They are called by triggers and can be called directly for analytics.
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/03_functions.sql
-- ============================================================

-- ============================================================
-- FUNCTION 1: compute_order_totals
-- Calculates subtotal, 12% VAT, and final total for an order
--
-- Business Rule: Czech restaurant VAT = 12% (reduced rate for food service)
-- ============================================================
CREATE OR REPLACE FUNCTION compute_order_totals(p_order_id INT)
RETURNS TABLE (
    calc_subtotal NUMERIC,
    calc_vat      NUMERIC,
    calc_total    NUMERIC
) AS $$
DECLARE
    v_subtotal NUMERIC;
BEGIN
    -- Sum all line items: quantity * unit_price
    SELECT COALESCE(SUM(quantity * unit_price), 0)
    INTO v_subtotal
    FROM OrderDetails
    WHERE order_id = p_order_id;

    -- Czech VAT: 12% of subtotal
    RETURN QUERY
    SELECT
        v_subtotal,
        ROUND(v_subtotal * 0.12, 2) AS vat,
        ROUND(v_subtotal * 1.12, 2) AS total;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION compute_order_totals(INT) IS 'Calculates order financials: subtotal + 12% Czech VAT + total. Pure function - no side effects.';

-- ============================================================
-- FUNCTION 2: get_effective_price
-- Returns lunch price if order falls within lunch window, else regular price
--
-- Business Rule: Lunch specials apply Mon-Fri 11:00-14:30
-- ============================================================
CREATE OR REPLACE FUNCTION get_effective_price(p_menu_id INT, p_order_time TIMESTAMP)
RETURNS NUMERIC AS $$
DECLARE
    v_hour     INT := EXTRACT(HOUR FROM p_order_time);
    v_weekday  INT := EXTRACT(ISODOW FROM p_order_time); -- 1=Monday ... 7=Sunday
    v_regular  NUMERIC;
    v_lunch    NUMERIC;
BEGIN
    SELECT price_regular, price_lunch
    INTO v_regular, v_lunch
    FROM Menus
    WHERE menu_id = p_menu_id;

    -- Lunch special: weekday (Mon-Fri) AND hour 11-14 AND lunch price exists
    IF v_weekday BETWEEN 1 AND 5
       AND v_hour BETWEEN 11 AND 14
       AND v_lunch IS NOT NULL THEN
        RETURN v_lunch;
    END IF;

    RETURN v_regular;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_effective_price(INT, TIMESTAMP) IS 'Dynamic pricing: returns lunch price during lunch window (Mon-Fri 11:00-14:30), else regular price.';

-- ============================================================
-- FUNCTION 3: is_table_available
-- Checks if a table is free for a reservation (with 2-hour buffer)
--
-- Business Rule: 2-hour default dining duration
--
-- p_exclude_reservation_id lets an UPDATE of an existing booking ignore its own
-- row; without it a reservation always conflicts with itself.
-- ============================================================
-- Drop the old 3-argument signature so re-running this file on an existing
-- database does not leave an ambiguous overload behind.
DROP FUNCTION IF EXISTS is_table_available(INT, TIMESTAMP, INT);

CREATE OR REPLACE FUNCTION is_table_available(
    p_table_id INT,
    p_time     TIMESTAMP,
    p_duration_minutes INT DEFAULT 120,
    p_exclude_reservation_id INT DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    -- Table is available if NO confirmed/pending reservation overlaps
    -- Overlap = existing reservation starts before we finish AND ends after we start
    RETURN NOT EXISTS (
        SELECT 1
        FROM Reservations r
        WHERE r.table_id = p_table_id
          AND r.status IN ('confirmed', 'pending')
          AND (p_exclude_reservation_id IS NULL
               OR r.reservation_id <> p_exclude_reservation_id)
          AND r.reservation_time < (p_time + (p_duration_minutes || ' minutes')::INTERVAL)
          AND (r.reservation_time + (p_duration_minutes || ' minutes')::INTERVAL) > p_time
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION is_table_available(INT, TIMESTAMP, INT, INT) IS 'Table availability check with 2-hour overlap buffer. Pass p_exclude_reservation_id when re-checking an existing booking. Used by reservation system.';

-- ============================================================
-- FUNCTION 4: create_reservation
-- Creates a reservation with automatic conflict detection
--
-- Business Rule: No double-booking. Throws exception if table unavailable.
-- ============================================================
CREATE OR REPLACE FUNCTION create_reservation(
    p_user_id    INT,
    p_table_id   INT,
    p_time       TIMESTAMP,
    p_party_size SMALLINT,
    p_notes      TEXT DEFAULT NULL
) RETURNS INT AS $$
DECLARE
    new_id INT;
BEGIN
    IF NOT is_table_available(p_table_id, p_time) THEN
        RAISE EXCEPTION 'Table % is not available at %.', p_table_id, p_time;
    END IF;

    INSERT INTO Reservations (user_id, table_id, reservation_time, party_size, notes)
    VALUES (p_user_id, p_table_id, p_time, p_party_size, p_notes)
    RETURNING reservation_id INTO new_id;

    RETURN new_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_reservation(INT, INT, TIMESTAMP, SMALLINT, TEXT) IS 'Creates reservation with conflict check. Returns new reservation_id. Raises exception if table unavailable.';

-- ============================================================
-- FUNCTION 5: finalize_order
-- Recalculates order totals, applies delivery fee rules
--
-- Business Rules:
-- - Delivery fee: +49 CZK if subtotal < 350 CZK
-- - Discounts applied before totals
-- ============================================================
CREATE OR REPLACE FUNCTION finalize_order(p_order_id INT) RETURNS VOID AS $$
DECLARE
    v_subtotal NUMERIC;
    v_vat      NUMERIC;
    v_total    NUMERIC;
    v_type     TEXT;
    v_fee      NUMERIC := 0;
BEGIN
    -- Get calculated totals from compute_order_totals
    SELECT calc_subtotal, calc_vat, calc_total
    INTO v_subtotal, v_vat, v_total
    FROM compute_order_totals(p_order_id);

    -- Get order type for delivery fee rule
    SELECT order_type INTO v_type FROM Orders WHERE order_id = p_order_id;

    -- Delivery fee: 49 CZK if subtotal under 350 CZK (Wolt/Bolt style)
    IF v_type = 'delivery' AND v_subtotal < 350 THEN
        v_fee := 49;
    END IF;

    -- Update order with final amounts
    UPDATE Orders
    SET subtotal     = v_subtotal,
        vat_amount   = v_vat,
        total        = v_total + v_fee - COALESCE(discount_amount, 0),
        delivery_fee = v_fee
    WHERE order_id = p_order_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finalize_order(INT) IS 'Recalculates order totals after adding/removing items. Applies delivery fee rule. Called by trigger after each OrderDetails insert.';

-- ============================================================
-- FUNCTION 6: get_customer_lifetime_value
-- Returns total revenue generated by a customer
-- ============================================================
CREATE OR REPLACE FUNCTION get_customer_lifetime_value(p_user_id INT)
RETURNS NUMERIC AS $$
DECLARE
    v_ltv NUMERIC;
BEGIN
    SELECT COALESCE(SUM(total), 0)
    INTO v_ltv
    FROM Orders
    WHERE user_id = p_user_id
      AND status = 'completed';

    RETURN v_ltv;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_customer_lifetime_value(INT) IS 'Customer lifetime value: sum of all completed order totals. Core CRM metric.';

-- ============================================================
-- FUNCTION 7: get_menu_profitability
-- Returns revenue and volume metrics for a menu item
-- ============================================================
CREATE OR REPLACE FUNCTION get_menu_profitability(p_menu_id INT)
RETURNS TABLE (
    menu_name        VARCHAR,
    times_ordered    BIGINT,
    portions_sold    BIGINT,
    total_revenue    NUMERIC,
    avg_order_value  NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.name_en,
        COUNT(DISTINCT od.order_id)::BIGINT,
        SUM(od.quantity)::BIGINT,
        SUM(od.quantity * od.unit_price),
        CASE WHEN COUNT(DISTINCT od.order_id) > 0
             THEN ROUND(SUM(od.quantity * od.unit_price) / COUNT(DISTINCT od.order_id), 2)
             ELSE 0 END
    FROM Menus m
    JOIN OrderDetails od ON m.menu_id = od.menu_id
    JOIN Orders o ON od.order_id = o.order_id
    WHERE m.menu_id = p_menu_id
      AND o.status = 'completed'
    GROUP BY m.menu_id, m.name_en;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_menu_profitability(INT) IS 'Menu item profitability analysis: volume, revenue, and average order value contribution.';

-- ============================================================
-- FUNCTION 8: get_daily_summary
-- Returns daily operational KPIs for a specific date
-- ============================================================
CREATE OR REPLACE FUNCTION get_daily_summary(p_date DATE)
RETURNS TABLE (
    report_date        DATE,
    total_orders       BIGINT,
    dine_in_orders     BIGINT,
    delivery_orders    BIGINT,
    event_orders       BIGINT,
    total_revenue      NUMERIC,
    total_vat          NUMERIC,
    avg_order_value    NUMERIC,
    total_customers    BIGINT,
    new_customers      BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_date,
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE order_type = 'dine_in')::BIGINT,
        COUNT(*) FILTER (WHERE order_type = 'delivery')::BIGINT,
        COUNT(*) FILTER (WHERE order_type = 'event')::BIGINT,
        COALESCE(SUM(total), 0),
        COALESCE(SUM(vat_amount), 0),
        CASE WHEN COUNT(*) > 0 THEN ROUND(AVG(total), 2) ELSE 0 END,
        COUNT(DISTINCT user_id)::BIGINT,
        COUNT(DISTINCT user_id) FILTER (
            WHERE user_id NOT IN (
                SELECT user_id FROM Orders
                WHERE order_time < p_date AND status = 'completed'
            )
        )::BIGINT
    FROM Orders
    WHERE DATE(order_time) = p_date
      AND status = 'completed'
    GROUP BY p_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_daily_summary(DATE) IS 'Daily operational dashboard: orders by type, revenue, VAT, customer count, new customer acquisition.';

-- ============================================================
-- FUNCTIONS REGISTERED
-- ============================================================
-- Total: 8 functions
--
-- Pure Functions (no side effects):
--   - compute_order_totals      → Financial calculation
--   - get_effective_price       → Dynamic pricing
--   - is_table_available        → Reservation check
--   - get_customer_lifetime_value → CRM metric
--   - get_menu_profitability    → Product analytics
--   - get_daily_summary         → Operational dashboard
--
-- Side-Effect Functions:
--   - create_reservation        → Inserts reservation
--   - finalize_order            → Updates order totals
--
-- Called By:
--   - Triggers (auto): get_effective_price, finalize_order, compute_order_totals
--   - Application (manual): create_reservation, analytics functions
-- ============================================================
