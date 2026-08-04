-- ============================================================
-- Golden Dragon Prague - Operational Views
--
-- These views power daily restaurant operations:
-- - Kitchen queue (what to prepare now)
-- - Table status (occupancy + reservations)
-- - Allergen warnings (safety alerts)
-- - Daily revenue (accounting)
-- - Top dishes (inventory planning)
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/05_views.sql
-- ============================================================

-- ============================================================
-- VIEW 1: v_kitchen_queue
-- Real-time kitchen preparation list
--
-- Business Use: Kitchen staff see what needs to be cooked RIGHT NOW
-- ============================================================
CREATE OR REPLACE VIEW v_kitchen_queue AS
SELECT
    o.order_id,
    o.order_time,
    o.order_type,
    o.status,
    rt.table_number,
    u.full_name AS customer,
    m.name_en   AS dish,
    m.name_cz   AS dish_cz,
    od.quantity,
    od.line_note,
    od.spice_override,
    o.special_requests,
    m.estimated_prep_minutes
FROM Orders o
LEFT JOIN RestaurantTables rt ON o.table_id = rt.table_id
LEFT JOIN Users u            ON o.user_id = u.user_id
JOIN OrderDetails od         ON o.order_id = od.order_id
JOIN Menus m                 ON od.menu_id = m.menu_id
WHERE o.status IN ('new', 'confirmed', 'preparing')
ORDER BY
    CASE o.status WHEN 'new' THEN 1 WHEN 'confirmed' THEN 2 WHEN 'preparing' THEN 3 ELSE 4 END,
    o.order_time ASC;

COMMENT ON VIEW v_kitchen_queue IS 'Real-time kitchen queue. Sorted by urgency (new → confirmed → preparing). Kitchen uses this for prep prioritization.';

-- ============================================================
-- VIEW 2: v_table_status
-- Current table occupancy + upcoming reservations
--
-- Business Use: Host/hostess sees table availability at a glance
-- ============================================================
CREATE OR REPLACE VIEW v_table_status AS
SELECT
    rt.table_number,
    rt.capacity,
    rt.zone,
    o.order_id        AS current_order,
    o.status          AS order_status,
    o.order_type      AS current_order_type,
    r.reservation_id,
    r.reservation_time,
    r.party_size      AS reservation_party,
    r.notes           AS reservation_notes,
    r.status          AS reservation_status
FROM RestaurantTables rt
LEFT JOIN Orders o
    ON rt.table_id = o.table_id
    AND o.status NOT IN ('completed', 'cancelled')
LEFT JOIN Reservations r
    ON rt.table_id = r.table_id
    AND r.reservation_time BETWEEN NOW() AND NOW() + INTERVAL '4 hours'
    AND r.status = 'confirmed'
ORDER BY rt.zone, rt.table_number;

COMMENT ON VIEW v_table_status IS 'Table occupancy snapshot. Shows current orders and upcoming reservations. Used by front-of-house staff.';

-- ============================================================
-- VIEW 3: v_daily_revenue
-- Daily financial summary with VAT breakdown
--
-- Business Use: Daily accounting, tax reporting, cash reconciliation
-- ============================================================
CREATE OR REPLACE VIEW v_daily_revenue AS
SELECT
    DATE(order_time)                                  AS day,
    COUNT(*)                                          AS orders_count,
    SUM(subtotal)                                     AS subtotal,
    SUM(vat_amount)                                   AS vat_total,
    SUM(total)                                        AS revenue_total,
    SUM(delivery_fee)                                 AS delivery_fees,
    SUM(CASE WHEN order_type = 'dine_in' THEN total ELSE 0 END)  AS dine_in_revenue,
    SUM(CASE WHEN order_type = 'delivery' THEN total ELSE 0 END) AS delivery_revenue,
    SUM(CASE WHEN order_type = 'event' THEN total ELSE 0 END)    AS event_revenue,
    SUM(CASE WHEN order_type = 'takeaway' THEN total ELSE 0 END) AS takeaway_revenue
FROM Orders
WHERE status = 'completed'
GROUP BY DATE(order_time)
ORDER BY day DESC;

COMMENT ON VIEW v_daily_revenue IS 'Daily financial summary with VAT breakdown. Revenue split by order type. Essential for Czech tax reporting.';

-- ============================================================
-- VIEW 4: v_top_dishes
-- Best-selling menu items by volume and revenue
--
-- Business Use: Menu engineering, inventory planning, seasonal adjustments
-- ============================================================
CREATE OR REPLACE VIEW v_top_dishes AS
SELECT
    m.menu_id,
    m.name_en,
    m.name_cz,
    m.price_regular,
    COUNT(*)                                     AS times_ordered,
    SUM(od.quantity)                             AS portions_sold,
    SUM(od.quantity * od.unit_price)             AS revenue,
    ROUND(AVG(od.unit_price), 2)                 AS avg_selling_price,
    COUNT(DISTINCT od.order_id)                  AS order_count
FROM OrderDetails od
JOIN Menus m   ON od.menu_id = m.menu_id
JOIN Orders o  ON od.order_id = o.order_id
WHERE o.status = 'completed'
GROUP BY m.menu_id, m.name_en, m.name_cz, m.price_regular
ORDER BY portions_sold DESC;

COMMENT ON VIEW v_top_dishes IS 'Menu item performance: portions sold, revenue, and order frequency. Used for menu engineering decisions.';

-- ============================================================
-- VIEW 5: v_allergen_warnings
-- Safety-critical: which open orders contain allergens
--
-- Business Use: Kitchen cross-contamination prevention
-- Legal: EU Regulation 1169/2011 compliance
-- ============================================================
-- LEFT JOIN on MenuAllergens/Allergens, not INNER: with inner joins a dish only
-- reached the view if it already had at least one allergen row, so the 'SAFE'
-- branch of safety_flag was unreachable and an allergen-free dish simply
-- vanished from the kitchen's checklist. A dish missing from a safety view
-- reads as "not checked yet", which is exactly the ambiguity the view exists to
-- remove - every dish on every open order must appear, explicitly flagged.
-- Users is also LEFT-joined: a walk-in order has no user_id and must not be
-- dropped from a safety-critical view.
CREATE OR REPLACE VIEW v_allergen_warnings AS
SELECT
    o.order_id,
    o.status,
    o.order_type,
    rt.table_number,
    COALESCE(u.full_name, 'Walk-in / Unknown') AS customer,
    m.name_en     AS dish,
    COALESCE(string_agg(DISTINCT a.name_en, ', '), 'None declared') AS allergens_present,
    COUNT(DISTINCT ma.allergen_id)                                  AS allergen_count,
    CASE WHEN COUNT(DISTINCT ma.allergen_id) > 0 THEN 'WARNING' ELSE 'SAFE' END AS safety_flag,
    -- Cross-check against what the customer told us, so the kitchen sees the
    -- collision on one row instead of joining two views by eye.
    o.special_requests -> 'allergies' AS customer_declared_allergies
FROM Orders o
LEFT JOIN Users u            ON o.user_id = u.user_id
JOIN OrderDetails od         ON o.order_id = od.order_id
JOIN Menus m                 ON od.menu_id = m.menu_id
LEFT JOIN MenuAllergens ma   ON m.menu_id = ma.menu_id
LEFT JOIN Allergens a        ON ma.allergen_id = a.allergen_id
LEFT JOIN RestaurantTables rt ON o.table_id = rt.table_id
WHERE o.status NOT IN ('completed', 'cancelled')
GROUP BY o.order_id, o.status, o.order_type, rt.table_number, u.full_name, m.name_en, m.menu_id, o.special_requests
ORDER BY o.order_id, m.menu_id;

COMMENT ON VIEW v_allergen_warnings IS 'CRITICAL SAFETY VIEW: allergen declarations for every dish on every open order, including allergen-free dishes (safety_flag = SAFE). Kitchen uses this to prevent cross-contamination. EU legal requirement.';

-- ============================================================
-- VIEW 6: v_customer_order_history
-- Complete customer activity summary
--
-- Business Use: CRM, loyalty program management, re-engagement campaigns
-- ============================================================
CREATE OR REPLACE VIEW v_customer_order_history AS
SELECT
    u.user_id,
    u.username,
    u.full_name,
    u.email,
    u.phone,
    u.role,
    u.loyalty_points,
    COUNT(o.order_id)                                                  AS total_orders,
    COUNT(o.order_id) FILTER (WHERE o.status = 'completed')            AS completed_orders,
    COUNT(o.order_id) FILTER (WHERE o.status = 'cancelled')            AS cancelled_orders,
    SUM(CASE WHEN o.status = 'completed' THEN o.total ELSE 0 END)     AS lifetime_value,
    AVG(CASE WHEN o.status = 'completed' THEN o.total END)            AS avg_order_value,
    MAX(o.order_time)                                                  AS last_order_time,
    MIN(o.order_time)                                                  AS first_order_time
FROM Users u
LEFT JOIN Orders o ON u.user_id = o.user_id
WHERE u.role IN ('customer', 'vip')   -- 'vip' is a customer tier, not a separate audience
GROUP BY u.user_id, u.username, u.full_name, u.email, u.phone, u.role, u.loyalty_points
ORDER BY lifetime_value DESC NULLS LAST;

COMMENT ON VIEW v_customer_order_history IS 'Customer 360-view: order history, lifetime value, average order value, recency. Core CRM view.';

-- ============================================================
-- VIEW 7: v_pending_orders
-- Orders still awaiting action, oldest and most urgent first
--
-- Business Use: Operations dashboard, staff task assignment
--
-- This was a placeholder (`SELECT * FROM v_customer_order_history WHERE 1=0`)
-- that returned zero rows with customer-history columns, so the operations
-- dashboard it backs always looked empty - "nothing outstanding" is the most
-- dangerous thing an empty ops view can wrongly say.
--
-- "Pending" here means every status between placed and closed. Orders.status
-- has no literal 'pending' value; the open states are new -> confirmed ->
-- preparing -> ready -> out_for_delivery, and closed ones are completed and
-- cancelled.
-- ============================================================
-- Column list changes completely, and CREATE OR REPLACE VIEW cannot do that.
DROP VIEW IF EXISTS v_pending_orders;

CREATE VIEW v_pending_orders AS
WITH open_orders AS (
    SELECT
        o.order_id,
        o.order_time,
        o.status,
        o.order_type,
        o.source,
        COALESCE(u.full_name, 'Walk-in / Unknown') AS customer,
        u.phone                                    AS customer_phone,
        rt.table_number,
        emp.full_name                              AS assigned_staff,
        o.delivery_address ->> 'street'            AS delivery_street,
        o.special_requests ->> 'notes'             AS order_notes,
        o.total,
        items.item_count,
        items.total_items,
        items.est_prep_minutes,
        FLOOR(EXTRACT(EPOCH FROM (NOW() - o.order_time)) / 60)::INT AS minutes_waiting
    FROM Orders o
    LEFT JOIN Users u             ON o.user_id     = u.user_id
    LEFT JOIN RestaurantTables rt ON o.table_id    = rt.table_id
    LEFT JOIN Employees emp       ON o.employee_id = emp.employee_id
    LEFT JOIN LATERAL (
        SELECT COUNT(*)                                            AS item_count,
               COALESCE(SUM(od.quantity), 0)                       AS total_items,
               COALESCE(SUM(m.estimated_prep_minutes * od.quantity), 0) AS est_prep_minutes
        FROM OrderDetails od
        JOIN Menus m ON od.menu_id = m.menu_id
        WHERE od.order_id = o.order_id
    ) items ON TRUE
    WHERE o.status IN ('new', 'confirmed', 'preparing', 'ready', 'out_for_delivery')
)
SELECT
    *,
    CASE
        WHEN est_prep_minutes = 0                          THEN 'NO ITEMS'
        WHEN minutes_waiting > est_prep_minutes * 2        THEN 'OVERDUE'
        WHEN minutes_waiting > est_prep_minutes            THEN 'LATE'
        ELSE 'ON TRACK'
    END AS sla_flag
FROM open_orders
ORDER BY
    CASE status
        WHEN 'new' THEN 1 WHEN 'confirmed' THEN 2 WHEN 'preparing' THEN 3
        WHEN 'ready' THEN 4 WHEN 'out_for_delivery' THEN 5 ELSE 6
    END,
    order_time ASC;

COMMENT ON VIEW v_pending_orders IS 'Orders requiring action (new, confirmed, preparing, ready, out_for_delivery) with wait time, assigned staff and an SLA flag derived from the kitchen prep estimate. Backs the operations dashboard.';

-- ============================================================
-- VIEW 8: v_order_summary (enriched)
-- Complete order details with financial breakdown
--
-- Business Use: Accounting, dispute resolution, customer service
-- ============================================================
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    u.full_name                              AS customer,
    u.email,
    u.phone,
    o.order_time,
    o.order_type,
    o.source,
    o.status,
    o.special_requests,
    o.subtotal,
    o.vat_amount,
    o.delivery_fee,
    o.total,
    o.delivery_address,
    rt.table_number,
    e.event_date,
    e.location                               AS event_location,
    items.item_count,
    items.total_items,
    -- Aggregated in a LATERAL so a second payment row cannot double item_count,
    -- and so a partial payment is not reported as fully PAID.
    CASE
        WHEN pay.payment_count = 0                            THEN 'UNPAID'
        WHEN pay.paid_amount >= COALESCE(o.total, 0) - 0.01   THEN 'PAID'
        ELSE 'PARTIAL'
    END                                       AS payment_status,
    pay.paid_amount,
    pay.paid_at
FROM Orders o
-- LEFT JOIN: walk-in / phone orders have no user_id and must still appear.
LEFT JOIN Users u             ON o.user_id  = u.user_id
LEFT JOIN RestaurantTables rt ON o.table_id = rt.table_id
LEFT JOIN Events e            ON o.order_id = e.order_id
LEFT JOIN LATERAL (
    SELECT COUNT(*)                       AS item_count,
           COALESCE(SUM(od.quantity), 0)  AS total_items
    FROM OrderDetails od
    WHERE od.order_id = o.order_id
) items ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*)                     AS payment_count,
           COALESCE(SUM(p.amount), 0)   AS paid_amount,
           MAX(p.paid_at)               AS paid_at
    FROM Payments p
    WHERE p.order_id = o.order_id
) pay ON TRUE
ORDER BY o.order_time DESC;

COMMENT ON VIEW v_order_summary IS 'Comprehensive order view: customer, financials, items, payment status, event details. Single source of truth for order information.';

-- ============================================================
-- VIEW REGISTRATION
-- ============================================================
-- Operational Views:
--   v_kitchen_queue       → Kitchen operations
--   v_table_status        → Front-of-house
--   v_daily_revenue       → Finance/accounting
--   v_top_dishes          → Menu engineering
--   v_allergen_warnings   → Kitchen safety (CRITICAL)
--   v_customer_order_history → CRM
--   v_pending_orders      → Operations dashboard
--   v_order_summary       → General purpose
-- ============================================================
