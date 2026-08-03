-- ============================================================
-- Golden Dragon Prague - Full Setup (Master Script)
--
-- This script creates the complete database from scratch.
-- It runs all component scripts in the correct order.
--
-- Run: psql -U postgres -f sql/99_full_setup.sql
-- ============================================================

-- Abort immediately on the first error instead of continuing and printing
-- "Setup Complete" over a half-built database.
\set ON_ERROR_STOP on

\echo '=== Golden Dragon Prague Chinese Restaurant | Full Setup (English Version) ==='
\echo 'Database: golden_dragon_prague'
\echo 'Business: Chinese restaurant in Prague, Czech Republic'
\echo ''

-- Drop and recreate database
DROP DATABASE IF EXISTS golden_dragon_prague;
CREATE DATABASE golden_dragon_prague;

\c golden_dragon_prague

\echo ''
\echo '=== Step 1: Creating Schema ==='
\i sql/01_schema.sql

\echo ''
\echo '=== Step 2: Creating Indexes ==='
\i sql/02_indexes.sql

\echo ''
\echo '=== Step 3: Creating Business Logic Functions ==='
\i sql/03_functions.sql

\echo ''
\echo '=== Step 4: Creating Triggers ==='
\i sql/04_triggers.sql

\echo ''
\echo '=== Step 5: Creating Views ==='
\i sql/05_views.sql

\echo ''
\echo '=== Step 6: Creating Analytics Views ==='
\i sql/06_analytics_views.sql

\echo ''
\echo '=== Step 7: Inserting Sample Data ==='
\i sql/07_data.sql

\echo ''
\echo '=== Step 8: Creating Star Schema (Data Warehouse) ==='
\i sql/etl_star_schema.sql

\echo ''
\echo '=== Setup Complete ==='
\echo ''
\echo 'Database: golden_dragon_prague'
\echo ''
\echo 'Quick verification:'
\echo '  Tables:       SELECT tablename FROM pg_tables WHERE schemaname = ''public'';'
\echo '  Kitchen:      SELECT * FROM v_kitchen_queue;'
\echo '  Revenue:      SELECT * FROM v_daily_revenue;'
\echo '  Customers:    SELECT * FROM v_customer_rfm;'
\echo '  Allergens:    SELECT * FROM v_allergen_warnings;'
\echo ''
\echo 'To run all queries:'
\echo '  psql -d golden_dragon_prague -f sql/08_queries.sql'
\echo '  psql -d golden_dragon_prague -f sql/09_analytics_queries.sql'
\echo ''
