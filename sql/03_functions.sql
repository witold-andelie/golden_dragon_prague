-- ============================================================
-- Golden Dragon Prague - Business Logic Functions (PL/pgSQL)
--
-- These functions encode the core business rules of the restaurant.
-- They are called by triggers and can be called directly for analytics.
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/03_functions.sql
-- ============================================================

-- ============================================================
-- FUNCTION 0: is_lunch_window
-- THE single definition of the lunch special window.
--
-- Business Rule: Mon-Fri, 11:00 up to (but not including) 14:30.
--
-- Every consumer - pricing, analytics views, the star-schema ETL - must call
-- this instead of re-deriving the window. The rule used to be re-implemented
-- as `EXTRACT(HOUR ...) BETWEEN 11 AND 14`, which silently extends the window
-- to 14:59 and drifted apart from the documented 14:30 cut-off.
-- ============================================================
CREATE OR REPLACE FUNCTION is_lunch_window(p_ts TIMESTAMP)
RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_ts IS NOT NULL
       AND EXTRACT(ISODOW FROM p_ts) BETWEEN 1 AND 5   -- 1=Monday ... 5=Friday
       AND p_ts::TIME >= TIME '11:00'
       AND p_ts::TIME <  TIME '14:30';
$$;

COMMENT ON FUNCTION is_lunch_window(TIMESTAMP) IS 'Single source of truth for the lunch special window: Mon-Fri, [11:00, 14:30). Half-open interval - an order placed exactly at 14:30 is already regular pricing.';

-- ============================================================
-- FUNCTION 0b: get_platform_commission_rate
-- Commission a sales channel charges on gross order value.
--
-- Business Rule: only third-party delivery platforms take a cut. Walk-in,
-- phone and own-website orders cost 0%. Rates mirror dim_channel.
-- ============================================================
CREATE OR REPLACE FUNCTION get_platform_commission_rate(p_source VARCHAR)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_source
        WHEN 'wolt'      THEN 0.22
        WHEN 'bolt'      THEN 0.22
        WHEN 'uber_eats' THEN 0.25
        ELSE 0
    END;
$$;

COMMENT ON FUNCTION get_platform_commission_rate(VARCHAR) IS 'Platform commission by sales channel: Wolt/Bolt 22%, Uber Eats 25%, direct channels (walk-in, phone, website) 0%. Kept in sync with dim_channel.platform_fee_pct.';

-- ============================================================
-- FUNCTION 1: compute_order_totals
-- THE single definition of order financials.
--
-- Business Rules (order of operations matters):
--   1. subtotal      = SUM(quantity * unit_price)   -- net of VAT
--   2. discount      = capped at subtotal (a discount cannot exceed the goods)
--   3. delivery fee  = 49 CZK on delivery orders under 350 CZK net of discount
--   4. taxable base  = subtotal - discount + delivery fee
--   5. VAT           = base * vat_rate   (12% Czech reduced rate for food service)
--   6. total         = base + VAT
--
-- The discount reduces the TAXABLE BASE - it is a price reduction, not a
-- post-tax rebate. Applying it after VAT (the old behaviour) over-declares
-- output VAT to the tax office and makes total != base + VAT.
-- ============================================================
-- The return type changes, and CREATE OR REPLACE cannot change a function's
-- result type, so drop the old signature first.
DROP FUNCTION IF EXISTS compute_order_totals(INT);

CREATE OR REPLACE FUNCTION compute_order_totals(p_order_id INT)
RETURNS TABLE (
    calc_subtotal     NUMERIC,
    calc_discount     NUMERIC,
    calc_delivery_fee NUMERIC,
    calc_taxable_base NUMERIC,
    calc_vat          NUMERIC,
    calc_total        NUMERIC
) AS $$
DECLARE
    v_subtotal NUMERIC;
    v_discount NUMERIC;
    v_fee      NUMERIC := 0;
    v_type     TEXT;
    v_rate     NUMERIC;
    v_base     NUMERIC;
    v_vat      NUMERIC;
BEGIN
    -- Sum all line items: quantity * unit_price
    SELECT COALESCE(SUM(quantity * unit_price), 0)
    INTO v_subtotal
    FROM OrderDetails
    WHERE order_id = p_order_id;

    -- vat_rate lives on the order so a historical rate stays reproducible;
    -- do not hardcode 0.12 here or reprinting an old invoice silently re-rates it.
    SELECT o.order_type, COALESCE(o.discount_amount, 0), COALESCE(o.vat_rate, 0.12)
    INTO v_type, v_discount, v_rate
    FROM Orders o
    WHERE o.order_id = p_order_id;

    v_discount := LEAST(GREATEST(v_discount, 0), v_subtotal);

    -- Delivery fee: 49 CZK if the discounted goods value is under 350 CZK
    IF v_type = 'delivery' AND (v_subtotal - v_discount) < 350 THEN
        v_fee := 49;
    END IF;

    v_base := v_subtotal - v_discount + v_fee;
    v_vat  := ROUND(v_base * v_rate, 2);

    RETURN QUERY SELECT v_subtotal, v_discount, v_fee, v_base, v_vat, ROUND(v_base + v_vat, 2);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION compute_order_totals(INT) IS 'Single source of truth for order financials. Discount reduces the taxable base, then VAT (Orders.vat_rate, 12% Czech reduced rate) is applied to subtotal - discount + delivery fee. Pure read - no side effects.';

-- ============================================================
-- FUNCTION 2: get_effective_price
-- Returns lunch price if order falls within lunch window, else regular price
--
-- Business Rule: Lunch specials apply Mon-Fri 11:00-14:30 (see is_lunch_window)
-- ============================================================
CREATE OR REPLACE FUNCTION get_effective_price(p_menu_id INT, p_order_time TIMESTAMP)
RETURNS NUMERIC AS $$
DECLARE
    v_regular  NUMERIC;
    v_lunch    NUMERIC;
BEGIN
    SELECT price_regular, price_lunch
    INTO v_regular, v_lunch
    FROM Menus
    WHERE menu_id = p_menu_id;

    -- Window rule is owned by is_lunch_window(); never re-derive it here.
    IF v_lunch IS NOT NULL AND is_lunch_window(p_order_time) THEN
        RETURN v_lunch;
    END IF;

    RETURN v_regular;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_effective_price(INT, TIMESTAMP) IS 'Dynamic pricing: returns lunch price during is_lunch_window() (Mon-Fri 11:00-14:30), else regular price.';

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
-- Persists the financials computed by compute_order_totals()
--
-- This function deliberately contains NO arithmetic. The delivery-fee rule and
-- the discount/VAT ordering used to be duplicated here and in
-- compute_order_totals(), and the two copies disagreed: this one added the fee
-- after VAT and subtracted the discount after VAT, so Orders.total did not
-- equal subtotal + vat_amount + delivery_fee - discount for any order that had
-- either. All of it now lives in compute_order_totals().
-- ============================================================
CREATE OR REPLACE FUNCTION finalize_order(p_order_id INT) RETURNS VOID AS $$
BEGIN
    UPDATE Orders o
    SET subtotal        = c.calc_subtotal,
        discount_amount = c.calc_discount,
        delivery_fee    = c.calc_delivery_fee,
        vat_amount      = c.calc_vat,
        total           = c.calc_total
    FROM compute_order_totals(p_order_id) c
    WHERE o.order_id = p_order_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION finalize_order(INT) IS 'Writes the financials from compute_order_totals() onto the order. Called by trigger after each OrderDetails insert. Holds no arithmetic of its own.';

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
-- Total: 10 functions
--
-- Business-Rule Primitives (IMMUTABLE, one definition each):
--   - is_lunch_window             → Lunch special window (Mon-Fri 11:00-14:30)
--   - get_platform_commission_rate → Channel commission (Wolt/Bolt 22%, direct 0%)
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
--   - Views/ETL: is_lunch_window, get_platform_commission_rate
-- ============================================================
