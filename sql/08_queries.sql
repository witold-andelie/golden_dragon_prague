-- ============================================================
-- Golden Dragon Prague - Operational Queries
--
-- These are the queries restaurant staff run daily.
-- Also useful for understanding the data model.
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/08_queries.sql
-- ============================================================

-- ============================================================
-- 1. KITCHEN: What needs to be prepared right now
-- ============================================================
SELECT * FROM v_kitchen_queue;

-- ============================================================
-- 2. FRONT-OF-HOUSE: Current table occupancy and reservations
-- ============================================================
SELECT * FROM v_table_status;

-- ============================================================
-- 3. SAFETY: Allergen warnings on open orders (CRITICAL)
-- ============================================================
SELECT * FROM v_allergen_warnings;

-- ============================================================
-- 4. FINANCE: Daily revenue with VAT breakdown (last 7 days)
-- ============================================================
SELECT * FROM v_daily_revenue LIMIT 7;

-- ============================================================
-- 5. MENU: Best selling dishes
-- ============================================================
SELECT * FROM v_top_dishes LIMIT 5;

-- ============================================================
-- 6. DELIVERY: Orders from Wolt/Bolt in last 7 days
-- ============================================================
SELECT
    order_id,
    order_time,
    order_type,
    total,
    delivery_fee,
    source,
    delivery_address ->> 'street' AS street,
    delivery_address ->> 'city'   AS city,
    special_requests ->> 'notes'  AS notes
FROM Orders
WHERE source IN ('wolt', 'bolt')
  AND order_time >= NOW() - INTERVAL '7 days'
ORDER BY order_time DESC;

-- ============================================================
-- 7. CRM: VIP customers with high loyalty points
-- ============================================================
SELECT
    full_name,
    email,
    phone,
    loyalty_points,
    role
FROM Users
WHERE role = 'vip' OR loyalty_points > 200
ORDER BY loyalty_points DESC;

-- ============================================================
-- 8. SAFETY: Orders with peanut allergens + customer allergy notes
-- ============================================================
SELECT
    o.order_id,
    u.full_name,
    m.name_en AS dish,
    o.special_requests ->> 'allergies' AS customer_allergies,
    string_agg(a.name_en, ', ') AS dish_allergens
FROM Orders o
JOIN Users u           ON o.user_id = u.user_id
JOIN OrderDetails od   ON o.order_id = od.order_id
JOIN Menus m           ON od.menu_id = m.menu_id
JOIN MenuAllergens ma  ON m.menu_id = ma.menu_id
JOIN Allergens a       ON ma.allergen_id = a.allergen_id
WHERE a.code = '5'  -- Peanuts
  AND o.status NOT IN ('completed', 'cancelled')
GROUP BY o.order_id, u.full_name, m.name_en, o.special_requests
ORDER BY o.order_id;

-- ============================================================
-- 9. MENU: Lunch menu usage statistics
-- ============================================================
SELECT
    COUNT(*) AS lunch_orders,
    SUM(od.quantity) AS portions,
    ROUND(AVG(od.unit_price), 2) AS avg_lunch_price,
    ROUND(SUM(od.quantity * od.unit_price), 2) AS lunch_revenue
FROM OrderDetails od
JOIN Orders o  ON od.order_id = o.order_id
JOIN Menus m   ON od.menu_id = m.menu_id
WHERE o.order_time::TIME BETWEEN '11:00' AND '14:30'
  AND m.price_lunch IS NOT NULL
  AND o.status = 'completed'
  AND EXTRACT(ISODOW FROM o.order_time) BETWEEN 1 AND 5;  -- Weekdays only

-- ============================================================
-- 10. RESERVATIONS: This week's confirmed bookings
-- ============================================================
SELECT
    r.reservation_time,
    rt.table_number,
    rt.zone,
    u.full_name,
    r.party_size,
    r.notes
FROM Reservations r
JOIN RestaurantTables rt ON r.table_id = rt.table_id
LEFT JOIN Users u        ON r.user_id = u.user_id
WHERE r.reservation_time BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
  AND r.status = 'confirmed'
ORDER BY r.reservation_time;

-- ============================================================
-- 11. OPERATIONS: Average time since order by type
-- ============================================================
SELECT
    order_type,
    COUNT(*) AS count,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - order_time)) / 60)) AS avg_minutes_since_order
FROM Orders
WHERE status NOT IN ('completed', 'cancelled')
GROUP BY order_type
ORDER BY avg_minutes_since_order DESC;

-- ============================================================
-- 12. REVENUE: Revenue by order source
-- ============================================================
SELECT
    source,
    COUNT(*) AS orders,
    SUM(total) AS revenue,
    ROUND(AVG(total), 2) AS avg_order_value,
    SUM(delivery_fee) AS total_delivery_fees
FROM Orders
WHERE status = 'completed'
GROUP BY source
ORDER BY revenue DESC;

-- ============================================================
-- 13. SAFETY: Dishes with many allergens (kitchen warning list)
-- ============================================================
SELECT
    m.name_en,
    COUNT(ma.allergen_id) AS allergen_count,
    string_agg(a.name_en, '; ') AS allergens
FROM Menus m
JOIN MenuAllergens ma ON m.menu_id = ma.menu_id
JOIN Allergens a      ON ma.allergen_id = a.allergen_id
GROUP BY m.menu_id, m.name_en
HAVING COUNT(ma.allergen_id) >= 3
ORDER BY allergen_count DESC;

-- ============================================================
-- 14. BUSINESS: Test business function - compute_order_totals
-- ============================================================
SELECT * FROM compute_order_totals(1);

-- ============================================================
-- 15. ANALYTICS: Table usage frequency
-- ============================================================
SELECT
    rt.table_number,
    rt.zone,
    rt.capacity,
    COUNT(o.order_id) AS times_used,
    SUM(o.total) AS total_revenue
FROM RestaurantTables rt
LEFT JOIN Orders o ON rt.table_id = o.table_id AND o.status = 'completed'
GROUP BY rt.table_id, rt.table_number, rt.zone, rt.capacity
ORDER BY times_used DESC;

-- ============================================================
-- 16. DELIVERY: Customer addresses for delivery orders
-- ============================================================
SELECT
    u.full_name,
    o.delivery_address ->> 'street'  AS street,
    o.delivery_address ->> 'city'    AS city,
    o.delivery_address ->> 'postal'  AS postal,
    o.total,
    o.order_time,
    o.source
FROM Orders o
JOIN Users u ON o.user_id = u.user_id
WHERE o.order_type = 'delivery'
  AND o.status = 'completed'
ORDER BY o.order_time DESC;

-- ============================================================
-- 17. OPERATIONS: Revenue by day of week (staffing insights)
-- ============================================================
SELECT
    TO_CHAR(order_time, 'FMDay') AS weekday,
    TO_CHAR(order_time, 'FMMonth') AS month,
    COUNT(*) AS orders,
    SUM(total) AS revenue,
    ROUND(AVG(total), 2) AS avg_order_value
FROM Orders
WHERE status = 'completed'
GROUP BY weekday, EXTRACT(DOW FROM order_time), TO_CHAR(order_time, 'FMMonth')
ORDER BY EXTRACT(DOW FROM order_time), revenue DESC;

-- ============================================================
-- 18. INVENTORY: Low stock alert
-- ============================================================
SELECT
    m.name_en,
    i.quantity AS remaining,
    m.price_regular,
    CASE
        WHEN i.quantity = 0 THEN 'OUT OF STOCK'
        WHEN i.quantity < 20 THEN 'CRITICAL'
        WHEN i.quantity < 50 THEN 'LOW'
        ELSE 'OK'
    END AS stock_status
FROM Inventory i
JOIN Menus m ON i.menu_id = m.menu_id
ORDER BY i.quantity ASC;

-- ============================================================
-- 19. FINANCE: Completed orders with full financial breakdown
-- ============================================================
SELECT
    o.order_id,
    o.order_time,
    u.full_name,
    o.subtotal,
    o.vat_amount,
    o.delivery_fee,
    o.discount_amount,
    o.total,
    o.order_type,
    o.source
FROM Orders o
JOIN Users u ON o.user_id = u.user_id
WHERE o.status = 'completed'
ORDER BY o.order_time DESC;

-- ============================================================
-- 20. ANALYTICS: Customer order frequency distribution
-- ============================================================
SELECT
    order_frequency,
    COUNT(*) AS customer_count
FROM (
    SELECT
        u.user_id,
        COUNT(o.order_id) AS order_frequency
    FROM Users u
    LEFT JOIN Orders o ON u.user_id = o.user_id AND o.status = 'completed'
    WHERE u.role IN ('customer', 'vip')   -- 'vip' is a customer tier, not a separate audience
    GROUP BY u.user_id
) sub
GROUP BY order_frequency
ORDER BY order_frequency;

-- ============================================================
-- 21. BUSINESS: Call business function for customer LTV
-- ============================================================
SELECT
    u.full_name,
    get_customer_lifetime_value(u.user_id) AS lifetime_value
FROM Users u
WHERE u.role IN ('customer', 'vip')   -- 'vip' is a customer tier, not a separate audience
ORDER BY lifetime_value DESC;

-- ============================================================
-- 22. JSONB: Extract dietary preferences from orders
-- ============================================================
SELECT
    order_id,
    special_requests ->> 'diet' AS diet_preference,
    special_requests ->> 'notes' AS notes,
    special_requests ->> 'spicy' AS spice_preference,
    special_requests ->> 'allergies' AS allergies
FROM Orders
WHERE special_requests IS NOT NULL
  AND special_requests ->> 'diet' IS NOT NULL
ORDER BY order_id;

-- ============================================================
-- 23. ETL TEST: Verify all orders have valid totals (data quality)
-- ============================================================
SELECT
    o.order_id,
    o.total,
    compute_order_totals(o.order_id) AS expected_totals
FROM Orders o
WHERE o.status = 'completed'
ORDER BY o.order_id;

-- ============================================================
-- 24. OPERATIONS: Upcoming reservations (next 7 days)
-- ============================================================
SELECT
    r.reservation_time,
    rt.table_number,
    rt.capacity,
    u.full_name,
    r.party_size,
    r.notes,
    CASE
        WHEN r.party_size > rt.capacity THEN 'OVERBOOKED'
        ELSE 'OK'
    END AS capacity_check
FROM Reservations r
JOIN RestaurantTables rt ON r.table_id = rt.table_id
LEFT JOIN Users u ON r.user_id = u.user_id
WHERE r.reservation_time BETWEEN NOW() AND NOW() + INTERVAL '7 days'
  AND r.status = 'confirmed'
ORDER BY r.reservation_time;
