# Golden Dragon Prague - Chinese Restaurant Database

**A production-quality PostgreSQL database project demonstrating advanced SQL, data analytics, and business intelligence capabilities.**

---

## Project Overview

This project is a complete database solution for **Golden Dragon (Zlatý Drak)**, a fictional Chinese restaurant operating in Prague, Czech Republic. It models real-world restaurant operations with accurate Czech business rules: 12% VAT, EU allergen labeling, lunch specials, delivery platforms (Wolt/Bolt), table reservations, and a loyalty program.

**Why this project?** It demonstrates mastery of:
- **Advanced SQL**: CTEs, window functions, GIN indexes, JSONB
- **PL/pgSQL**: Stored procedures, functions, triggers
- **Data Modeling**: Star schema, normalization, slowly changing dimensions
- **Business Intelligence**: RFM segmentation, cohort analysis, revenue forecasting
- **Data Pipeline**: ETL procedures, data quality checks, audit logging
- **Python Integration**: ETL scripts, analytics connector, visualization

---

## Quick Start

### Prerequisites
- PostgreSQL 12+ (tested on PostgreSQL 17)
- Python 3.8+ (for analytics scripts)
- psycopg2-binary and pandas (for Python scripts)

### 1-Click Setup

```bash
# Create the complete database
psql -U postgres -f sql/99_full_setup.sql

# Verify it works
psql -d golden_dragon_prague -c "SELECT * FROM v_kitchen_queue;"
psql -d golden_dragon_prague -c "SELECT * FROM v_customer_rfm;"
```

### Run Queries

```bash
# Operational queries (daily restaurant operations)
psql -d golden_dragon_prague -f sql/08_queries.sql

# Advanced analytics queries
psql -d golden_dragon_prague -f sql/09_analytics_queries.sql
```

### Generate Analytics Report

```bash
# Install Python dependencies
pip install psycopg2-binary pandas matplotlib seaborn

# Export data to CSV
python scripts/export_csv.py

# Generate HTML dashboard
python scripts/analyze.py
```

---

## Project Structure

```
golden_dragon_prague/
├── sql/
│   ├── 01_schema.sql          # 13 tables with full documentation
│   ├── 02_indexes.sql         # B-tree + GIN indexes
│   ├── 03_functions.sql       # 8 PL/pgSQL business functions
│   ├── 04_triggers.sql        # 7 triggers (validation, audit, automation)
│   ├── 05_views.sql           # 8 operational views
│   ├── 06_analytics_views.sql # 11 advanced BI views
│   ├── 07_data.sql            # Realistic sample data (15+ orders)
│   ├── 08_queries.sql         # 24 operational queries
│   ├── 09_analytics_queries.sql # 20 advanced analytics queries
│   ├── etl_star_schema.sql    # Star schema + ETL procedures
│   └── 99_full_setup.sql      # Master setup script
├── docs/
│   ├── README.md              # This file
│   ├── ARCHITECTURE.md        # Design decisions explained
│   ├── INTERVIEW_GUIDE.md     # Q&A prep for interviews
│   └── BI_DASHBOARD.md        # Business metrics documentation
├── scripts/
│   ├── export_csv.py          # ETL data exporter
│   └── analyze.py             # Analytics connector + HTML dashboard
├── erd/
│   └── ERD_description.md     # Entity relationship documentation
└── samples/
    └── dashboard_output/      # Generated CSV exports and reports
```

---

## Technical Specifications

| Component | Count | Details |
|-----------|-------|---------|
| Tables | 13 | 3NF normalized, foreign keys, check constraints |
| Indexes | 14+ | B-tree + GIN (JSONB), composite indexes |
| Functions | 10 | PL/pgSQL: pricing, VAT, reservations, analytics |
| Triggers | 7 | BEFORE/AFTER, conditional, audit trail |
| Views | 19 | Operational (8) + Analytics (11) |
| Stored Procedures | 3 | ETL pipeline, data quality checks |
| JSONB Columns | 2 | GIN indexed for fast queries |
| Sample Records | 80+ | Realistic Prague restaurant data |

---

## Key Features

### 1. Realistic Business Logic
- **12% Czech VAT**: Automatically calculated by `compute_order_totals()`
- **Lunch Specials**: Time-based pricing (Mon-Fri 11:00-14:30) via `get_effective_price()`
- **14 EU Allergens**: Linked to dishes, critical kitchen warnings
- **Delivery Platforms**: Wolt, Bolt with estimated platform fees (~22%)
- **Loyalty Program**: Automatic point accrual on order completion (1 pt per 50 CZK)

### 2. Data Integrity
- **Foreign Keys**: All relationships enforced
- **CHECK Constraints**: Role enums, status enums, quantity > 0
- **BEFORE Triggers**: Stock validation, pricing, reservation conflict prevention
- **Audit Trail**: `OrderAuditLog` table tracks all status changes

### 3. Advanced Analytics
- **RFM Segmentation**: Quintile-based customer tiers (Champion, Loyal, At Risk, Lost)
- **Cohort Analysis**: Customer retention by first purchase month
- **Revenue Forecasting**: 7-day and 30-day moving averages
- **Window Functions**: LAG, LEAD, NTILE, ROW_NUMBER, running totals
- **Pareto Analysis**: 80/20 rule applied to customer revenue

### 4. Data Warehouse Pattern
- **Star Schema**: 5 dimensions + 1 fact table
- **ETL Procedures**: `sp_load_fact_orders()`, `sp_run_data_quality_checks()`
- **Materialized Views**: Pre-computed daily KPIs
- **SCD Support**: Slowly changing dimensions for historical tracking

---

## Business Metrics Dashboard

| Metric | View/Query | Business Value |
|--------|-----------|----------------|
| Daily Revenue | `v_daily_revenue` | Financial reporting, tax compliance |
| Kitchen Queue | `v_kitchen_queue` | Operations, prep prioritization |
| Allergen Warnings | `v_allergen_warnings` | Safety, EU compliance |
| Customer Segments | `v_customer_rfm` | Marketing targeting, loyalty tiers |
| Revenue Forecast | `v_revenue_forecast` | Financial planning |
| Channel Performance | `v_source_performance` | Marketing budget allocation |
| Hourly Demand | `v_hourly_demand_patterns` | Staff scheduling |
| VAT Breakdown | `v_vat_breakdown_monthly` | Czech tax filing |

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Database | PostgreSQL 17 | Data storage, business logic, analytics |
| Language | SQL (PL/pgSQL) | Stored procedures, triggers, functions |
| Indexing | B-tree, GIN | Query optimization, JSONB search |
| Analytics | Python 3 + pandas | Data export, analysis, visualization |
| Visualization | matplotlib, seaborn | Charts and HTML dashboard |
| Export | CSV | BI tool integration (Tableau, Power BI, SAP Analytics Cloud) |

---

## Interview Highlights

This project demonstrates skills relevant to SAP Data Analysis:

1. **SQL Mastery**: Advanced queries with window functions, CTEs, ROLLUP
2. **Data Modeling**: 3NF + star schema, understanding trade-offs
3. **Business Logic**: Triggers and functions encoding real business rules
4. **Data Quality**: Audit trails, validation procedures, anomaly detection
5. **ETL Skills**: Stored procedures for data pipeline simulation
6. **Analytics**: RFM, cohort analysis, forecasting - core BI techniques
7. **Integration**: Python connector showing end-to-end data workflow
8. **Documentation**: Professional README, architecture docs, interview guide

---

## Sample Queries

```sql
-- RFM Customer Segmentation
SELECT segment, COUNT(*) as customers, ROUND(AVG(monetary), 2) as avg_ltv
FROM v_customer_rfm
GROUP BY segment
ORDER BY avg_ltv DESC;

-- Revenue with Moving Average
SELECT month, revenue, ma_7d, rolling_3mo_avg
FROM v_monthly_revenue_trends;

-- Kitchen Safety Alert
SELECT * FROM v_allergen_warnings;

-- Channel Profitability
SELECT source, gross_revenue, estimated_platform_fees, estimated_net_revenue
FROM v_source_performance;
```

---

## License

Academic project. Feel free to use as a portfolio piece or reference implementation.

---

## Author

Built as a semester database project, enhanced for SAP Data Analysis interview preparation.
