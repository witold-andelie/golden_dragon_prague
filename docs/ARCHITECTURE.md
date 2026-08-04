# Golden Dragon Prague - Architecture Documentation

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     RESTAURANT OPERATIONS                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │   POS    │  │  Kitchen │  │   Wait   │  │   Delivery   │   │
│  │  System  │  │ Display  │  │   Staff  │  │   Drivers    │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │
│       │              │             │                 │           │
│       ▼              ▼             ▼                 ▼           │
│              ┌─────────────────────────────────────┐            │
│              │     PostgreSQL Database              │            │
│              │  ┌─────────────────────────────┐    │            │
│              │  │     Operational Layer        │    │            │
│              │  │  (13 tables, triggers)       │    │            │
│              │  └─────────────────────────────┘    │            │
│              │  ┌─────────────────────────────┐    │            │
│              │  │     Analytics Layer          │    │            │
│              │  │  (11 BI views, functions)    │    │            │
│              │  └─────────────────────────────┘    │            │
│              │  ┌─────────────────────────────┐    │            │
│              │  │     Data Warehouse Layer     │    │            │
│              │  │  (Star schema, ETL)          │    │            │
│              │  └─────────────────────────────┘    │            │
│              └─────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
                   ┌──────────────────┐
                   │  Analytics Tools │
                   │  (Python/BI)     │
                   └──────────────────┘
```

## Layer 1: Operational Database

### Design Philosophy: 3NF (Third Normal Form)

All operational tables are in Third Normal Form:
- No repeating groups
- No partial dependencies
- No transitive dependencies

**Trade-off**: Some denormalization in `OrderDetails.unit_price` (captures price at order time for historical accuracy).

### Table Relationships

```
Users (1) ──────< (N) Orders (1) ──────< (N) OrderDetails (N) >────── (1) Menus
                                    >────── (1) Payments
                                    >────── (1) Events

RestaurantTables (1) <───── (N) Orders
                       <───── (N) Reservations

Employees (1) <───── (N) Orders

MenuCategories (1) >───── (N) Menus (N) >───── (1) Inventory
                                     >─────< (N) MenuAllergens <───── (1) Allergens
```

### Why These Tables?

| Table | Justification |
|-------|---------------|
| `Users` | Separate from Employees: customers have different attributes (loyalty points, dietary notes) |
| `OrderDetails` | Not embedded in Orders: one order has multiple items, need independent pricing |
| `MenuAllergens` | Junction table: many-to-many (one dish has many allergens, one allergen appears in many dishes) |
| `Events` | Separate from Orders: events have unique attributes (expected_guests, setup_notes) |
| `Payments` | Separate: supports split payments, multiple methods per order |

## Layer 2: Business Logic (PL/pgSQL)

### Function Architecture

```
User/Trigger
    │
    ▼
get_effective_price() ──► Dynamic pricing (lunch vs regular)
compute_order_totals() ──► Subtotal + 12% VAT + total
finalize_order() ──► Applies delivery fee rule + updates order
is_table_available() ──► Reservation conflict check
create_reservation() ──► Safe reservation creation
get_customer_lifetime_value() ──► CRM metric
get_menu_profitability() ──► Product analytics
get_daily_summary() ──► Operational dashboard
```

### Trigger Execution Order (Order Insert)

```
1. BEFORE INSERT OrderDetails: trg_check_inventory()
   └── Validates stock availability
   └── Raises exception if insufficient

2. BEFORE INSERT OrderDetails: trg_set_unit_price()
   └── Calls get_effective_price()
   └── Sets unit_price based on lunch window

3. INSERT OrderDetails row

4. AFTER INSERT OrderDetails: trg_after_order_detail()
   ├── Deducts from Inventory
   └── Calls finalize_order()
       └── Calls compute_order_totals()
       └── Applies delivery fee (49 CZK if < 350 CZK)
       └── Updates Orders subtotal, vat_amount, total, delivery_fee

5. [Later] UPDATE Orders status: trg_order_status()
   ├── Validates status transition
   └── Awards loyalty points on 'completed'

6. [Later] UPDATE Orders status: trg_order_audit_log()
   └── Logs to OrderAuditLog
```

### BEFORE vs AFTER Triggers

| Timing | Use Case | Example |
|--------|----------|---------|
| **BEFORE** | Validation, data preparation | Stock check, dynamic pricing |
| **AFTER** | Side effects, cascading updates | Inventory deduction, total recalculation, loyalty points |

## Layer 3: Index Strategy

### Why These Indexes?

| Index | Type | Purpose | Query Pattern |
|-------|------|---------|---------------|
| `idx_orders_status` | B-tree | Status filtering | Kitchen queue, pending orders |
| `idx_special_requests_gin` | GIN | JSONB search | Dietary restrictions |
| `idx_payments_order` | B-tree | Payment lookup per order | `v_order_summary`, accounting joins |
| `idx_orders_date_status` | Composite | Revenue reports, date ranges | `WHERE time=X AND status=Y`, and `time` alone |
| `idx_orders_type_status` | Composite | Channel performance | `WHERE type=X AND status=Y`, and `type` alone |

### Leftmost-Prefix Rule

A B-tree index on `(a, b)` already serves every query an index on `(a)` alone
could — Postgres scans the leading column and ignores the rest. A single-column
index on the leading column of an existing composite is therefore never the
better plan, but still costs a write on every `INSERT`/`UPDATE`.

`idx_orders_time` and `idx_orders_type` were exactly that, and
`idx_inventory_menu` duplicated the index Postgres creates automatically for
`Inventory.menu_id UNIQUE`. All three are gone; `sql/02_indexes.sql` lists them
with a detection query so they do not come back.

The rule does not run in reverse: `(order_time, status)` cannot serve a filter
on `status` alone, which is why `idx_orders_status` stays.

### GIN Index on JSONB

```sql
-- Without GIN index: Sequential scan (slow for large tables)
SELECT * FROM Orders WHERE special_requests @> '{"diet": "vegetarian"}';

-- With GIN index: Index scan using GIN (fast)
CREATE INDEX idx_special_requests_gin ON Orders USING GIN (special_requests);
```

**Why JSONB?**
- Flexible schema: special_requests varies per order
- Supports indexing: GIN index for fast containment queries
- Query power: `@>`, `->>`, `jsonb_path_query`
- No need for separate columns for rare attributes

## Layer 4: Analytics Layer

### Window Functions Used

| Function | Use Case | Example |
|----------|----------|---------|
| `LAG()` | Previous row value | Month-over-month growth |
| `LEAD()` | Next row value | Day-over-day comparison |
| `ROW_NUMBER()` | Sequential ranking | Top customers |
| `RANK()` | Ranking with gaps | Pareto analysis |
| `NTILE()` | Quartile/percentile | RFM segmentation |
| `AVG() OVER()` | Moving average | Revenue forecasting |
| `SUM() OVER()` | Running total | Cumulative revenue |
| `MODE()` | Most frequent value | Customer preferences |

### CTEs (Common Table Expressions)

Used for multi-step aggregations:
```sql
WITH rfm_base AS (...),      -- Step 1: Calculate R, F, M
     rfm_scores AS (...),    -- Step 2: Score each dimension
     rfm_segments AS (...)   -- Step 3: Assign segment
SELECT * FROM rfm_segments;
```

## Layer 5: Data Warehouse (Star Schema)

### Why Star Schema?

- **OLAP optimization**: Pre-joined dimensions for fast slicing/dicing
- **BI tool compatibility**: Standard schema for Tableau, Power BI, SAP Analytics Cloud
- **Historical tracking**: Slowly changing dimensions (SCD Type 2)

### Grain Definition

`fact_orders` grain: **One row per order line item**

This means:
- Order with 3 items = 3 rows in fact table
- Enables analysis: "Which menu items are ordered together?"

### Dimension Design

| Dimension | Grain | Slowly Changing? |
|-----------|-------|------------------|
| `dim_date` | One row per day | No (static) |
| `dim_customer` | One row per customer | Yes (SCD Type 2) |
| `dim_menu_item` | One row per menu item | Yes (price changes) |
| `dim_channel` | One row per source | No (static) |
| `dim_employee` | One row per employee | Yes (role changes) |

## Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   POS/Web    │────▶│   Orders     │────▶│ OrderDetails │
│   Order      │     │   Table      │     │   Table      │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  ▼
                                           ┌──────────────┐
                                           │   Triggers   │
                                           │  (Auto-deduct│
                                           │  inventory,  │
                                           │  calc totals)│
                                           └──────┬───────┘
                                                  │
                                                  ▼
                                           ┌──────────────┐
                                           │   ETL Load   │
                                           │ (sp_load_    │
                                           │  fact_orders)│
                                           └──────┬───────┘
                                                  │
                                                  ▼
                                           ┌──────────────┐
                                           │  fact_orders │
                                           │  (Star Fact) │
                                           └──────┬───────┘
                                                  │
                                                  ▼
                                           ┌──────────────┐
                                           │    BI/Reports│
                                           │ (Views, Python│
                                           │   Dashboard)  │
                                           └──────────────┘
```

## Scalability Considerations

### Current Scale
- ~80 records in main tables
- Designed for single-restaurant use

### Scaling to Multi-Location

```sql
-- Add location dimension
CREATE TABLE Locations (
    location_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    address TEXT,
    city VARCHAR(50)
);

-- Add to Orders
ALTER TABLE Orders ADD COLUMN location_id INT REFERENCES Locations(location_id);

-- Partition Orders by location + date
CREATE TABLE Orders_Prague PARTITION OF Orders
    FOR VALUES WITH (MODULUS 3, REMAINDER 0);
```

### Scaling to High Volume

| Bottleneck | Solution |
|------------|----------|
| Orders table growth | Partition by month |
| JSONB query speed | Add expression indexes |
| Fact table rebuild | Incremental ETL (load only new records) |
| Concurrent writes | Connection pooling (pgBouncer) |

---

*This architecture demonstrates systems thinking: operational efficiency, analytics readiness, and scalability planning.*
