# Golden Dragon Prague

A production-quality PostgreSQL database for a Chinese restaurant in Prague, Czech Republic. Demonstrates advanced SQL, data analytics, business intelligence, and data warehousing.

## Quick Start

```bash
# One-command setup
psql -U postgres -f sql/99_full_setup.sql

# Verify
psql -d golden_dragon_prague -c "SELECT * FROM v_kitchen_queue;"
```

## What's Inside

| Component | Count | Highlights |
|-----------|-------|-----------|
| Tables | 13 | 3NF, foreign keys, check constraints |
| Indexes | 14+ | B-tree + GIN for JSONB |
| Functions | 8 | Dynamic pricing, VAT, reservations, analytics |
| Triggers | 6 | Stock validation, audit trail, loyalty points |
| Views | 19 | 8 operational + 11 analytics (RFM, cohort, forecasting) |
| ETL Procedures | 3 | Star schema load, data quality checks |
| Python Scripts | 2 | CSV export + HTML dashboard generator |

## Documentation

- [Project README](docs/README.md) - Full overview and how to run
- [Architecture](docs/ARCHITECTURE.md) - Design decisions and data flow
- [Interview Guide](docs/INTERVIEW_GUIDE.md) - Q&A for data analysis interviews
- [BI Dashboard](docs/BI_DASHBOARD.md) - Business metrics and dashboard layout
- [ERD Description](erd/ERD_description.md) - Entity relationship documentation

## Tech Stack

PostgreSQL 17 · PL/pgSQL · JSONB · GIN Indexes · Window Functions · CTEs · Star Schema · Python (psycopg2, pandas, matplotlib)

## Run Analytics

```bash
pip install -r requirements.txt
python scripts/export_csv.py        # Export all views to CSV
python scripts/analyze.py            # Generate HTML dashboard
```

## Key Analytics

- **RFM Segmentation** - Customer tiers: Champion, Loyal, At Risk, Lost
- **Cohort Retention** - Track customer retention by acquisition month
- **Revenue Forecasting** - 7-day and 30-day moving averages
- **Pareto Analysis** - 80/20 rule for customer revenue
- **Hourly Demand Heatmap** - Staff scheduling optimization
