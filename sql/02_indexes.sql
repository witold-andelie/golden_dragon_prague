-- ============================================================
-- Golden Dragon Prague - Indexes
--
-- Index Strategy:
-- 1. B-tree indexes on high-cardinality filter columns (status, type, time)
-- 2. GIN index on JSONB for flexible metadata queries
-- 3. Composite indexes for common query patterns
-- 4. No redundant indexes - see the rule below, which this file now follows
--
-- THE LEFTMOST-PREFIX RULE
-- A B-tree index on (a, b) already answers every query a lone index on (a)
-- could: Postgres scans the leading column and ignores the rest. So a
-- single-column index whose column is the first column of an existing
-- composite index is dead weight - it is never the better plan, yet it still
-- has to be written on every INSERT/UPDATE and vacuumed on every cleanup.
-- The reverse is NOT true: (a, b) cannot serve a query filtering on b alone.
--
-- This header used to claim "no redundant indexes" while the file created
-- three. They are documented at the bottom rather than silently dropped, so
-- the next person does not re-add them.
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/02_indexes.sql
-- ============================================================

-- ============================================================
-- Orders table indexes
-- ============================================================
-- order_time and order_type are NOT indexed on their own here: they are the
-- leading columns of idx_orders_date_status and idx_orders_type_status below,
-- which cover the single-column cases for free.

-- Status filtering: kitchen queue, daily revenue, pending orders.
-- Needed standalone - status is the SECOND column of both composites, so
-- neither can serve `WHERE status = 'completed'` on its own.
CREATE INDEX idx_orders_status ON Orders(status);

-- Source attribution: Wolt/Bolt vs walk-in revenue comparison
CREATE INDEX idx_orders_source ON Orders(source);

-- User lookup: customer order history
CREATE INDEX idx_orders_user ON Orders(user_id);

-- Employee lookup: staff performance tracking
CREATE INDEX idx_orders_employee ON Orders(employee_id);

-- Table lookup: current table occupancy
CREATE INDEX idx_orders_table ON Orders(table_id);

-- ============================================================
-- JSONB GIN index (critical for flexible queries)
-- ============================================================
-- Accelerates JSONB containment queries (@>) and key lookups (->>)
-- Used for: dietary restrictions, allergy warnings, special instructions
-- Without this index, JSONB queries do sequential scans
CREATE INDEX idx_special_requests_gin ON Orders USING GIN (special_requests);

-- ============================================================
-- OrderDetails indexes
-- ============================================================
-- Join optimization: order_id is the most common join key
CREATE INDEX idx_orderdetails_order ON OrderDetails(order_id);

-- Menu performance: which dishes are popular
CREATE INDEX idx_orderdetails_menu ON OrderDetails(menu_id);

-- ============================================================
-- Reservations indexes
-- ============================================================
-- Time-based queries: upcoming reservations, table availability checks
CREATE INDEX idx_reservations_time ON Reservations(reservation_time);

-- Table availability function queries this index
CREATE INDEX idx_reservations_table ON Reservations(table_id);

-- Status filter: confirmed vs cancelled
CREATE INDEX idx_reservations_status ON Reservations(status);

-- ============================================================
-- Menu & Inventory indexes
-- ============================================================
-- Category browsing: starters, soups, main courses
CREATE INDEX idx_menus_category ON Menus(category_id);

-- Availability filter: seasonal menu changes
CREATE INDEX idx_menus_available ON Menus(is_available);

-- Inventory.menu_id is declared UNIQUE in 01_schema.sql, and Postgres backs
-- every UNIQUE constraint with a B-tree index automatically. An explicit
-- index on the same column is a byte-for-byte duplicate.

-- ============================================================
-- Payments indexes
-- ============================================================
-- Payments.order_id is a foreign key with no index. v_order_summary looks up
-- payments per order in a LATERAL subquery, and the accounting queries in
-- 08_queries.sql join the same way, so every one of them was doing a
-- sequential scan of Payments per order.
CREATE INDEX idx_payments_order ON Payments(order_id);

-- ============================================================
-- Composite indexes for common query patterns
-- ============================================================
-- Revenue by date + status (daily sales reports).
-- Also covers plain `WHERE order_time BETWEEN ...` via its leading column.
CREATE INDEX idx_orders_date_status ON Orders(order_time, status);

-- Delivery vs dine-in performance, filtered to completed orders.
-- Also covers plain `WHERE order_type = 'delivery'` via its leading column.
CREATE INDEX idx_orders_type_status ON Orders(order_type, status);

-- ============================================================
-- Deliberately NOT created (redundant - do not re-add)
-- ============================================================
-- idx_orders_time    ON Orders(order_time)  -> prefix of idx_orders_date_status
-- idx_orders_type    ON Orders(order_type)  -> prefix of idx_orders_type_status
-- idx_inventory_menu ON Inventory(menu_id)  -> duplicate of the UNIQUE constraint
--
-- To confirm nothing redundant has crept back in, this finds single-column
-- indexes whose column already leads another index on the same table:
--
--   SELECT a.indexrelid::regclass AS redundant, b.indexrelid::regclass AS covered_by
--   FROM pg_index a JOIN pg_index b
--     ON a.indrelid = b.indrelid AND a.indexrelid <> b.indexrelid
--   WHERE a.indnatts = 1
--     AND a.indkey[0] = b.indkey[0]
--     AND b.indnatts >= a.indnatts
--     AND NOT a.indisunique;
--
-- ============================================================
-- Index usage verification
-- ============================================================
-- Run these queries to verify indexes are being used:
--
-- EXPLAIN ANALYZE SELECT * FROM Orders WHERE status = 'completed';
-- Should show: Index Scan using idx_orders_status
--
-- EXPLAIN ANALYZE SELECT * FROM Orders WHERE special_requests @> '{"diet":"vegetarian"}';
-- Should show: Bitmap Heap Scan with GIN index
--
-- EXPLAIN ANALYZE SELECT * FROM Orders WHERE order_time BETWEEN '2025-01-01' AND '2025-12-31';
-- Should show: Index Scan using idx_orders_date_status  (leading column)
--
-- EXPLAIN ANALYZE SELECT SUM(amount) FROM Payments WHERE order_id = 14;
-- Should show: Index Scan using idx_payments_order
--
-- NOTE: on a 15-order seed database Postgres will pick a sequential scan for
-- most of these regardless - the whole table fits in one page, so a scan is
-- genuinely cheaper. Force the comparison with SET enable_seqscan = off, or
-- check the plans against a realistically sized copy.
-- ============================================================
