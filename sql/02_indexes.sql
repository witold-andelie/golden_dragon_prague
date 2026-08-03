-- ============================================================
-- Golden Dragon Prague - Indexes
--
-- Index Strategy:
-- 1. B-tree indexes on high-cardinality filter columns (status, type, time)
-- 2. GIN index on JSONB for flexible metadata queries
-- 3. Composite indexes for common join patterns
-- 4. No redundant indexes (each serves a distinct query pattern)
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/02_indexes.sql
-- ============================================================

-- ============================================================
-- Orders table indexes
-- ============================================================
-- Most common filter: orders by date range (daily reports, trends)
CREATE INDEX idx_orders_time ON Orders(order_time);

-- Status filtering: kitchen queue, daily revenue, pending orders
CREATE INDEX idx_orders_status ON Orders(status);

-- Order type filtering: delivery vs dine-in analytics
CREATE INDEX idx_orders_type ON Orders(order_type);

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

-- Stock level queries: low stock alerts, inventory management
CREATE INDEX idx_inventory_menu ON Inventory(menu_id);

-- ============================================================
-- Composite indexes for common query patterns
-- ============================================================
-- Revenue by date + status (daily sales reports)
CREATE INDEX idx_orders_date_status ON Orders(order_time, status);

-- Completed delivery orders for source performance analysis
CREATE INDEX idx_orders_type_status ON Orders(order_type, status);

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
-- Should show: Index Scan using idx_orders_time
-- ============================================================
