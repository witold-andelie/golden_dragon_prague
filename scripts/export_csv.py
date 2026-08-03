#!/usr/bin/env python3
"""
Golden Dragon Prague - ETL Data Exporter
=========================================

Exports all BI views and operational data to CSV files for external analysis.
Demonstrates ETL scripting skills relevant to SAP data analysis.

Usage:
    python scripts/export_csv.py

Output:
    samples/dashboard_output/*.csv

Requirements:
    pip install psycopg2-binary pandas
"""

import os
import sys
import csv
import psycopg2
from datetime import datetime

# Database connection configuration
DB_CONFIG = {
    'dbname': 'golden_dragon_prague',
    'user': 'postgres',
    'password': 'postgres',
    'host': 'localhost',
    'port': 5432
}

# Output directory
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'samples', 'dashboard_output')

# Views to export
VIEWS_TO_EXPORT = [
    ('v_kitchen_queue', 'kitchen_queue.csv'),
    ('v_table_status', 'table_status.csv'),
    ('v_daily_revenue', 'daily_revenue.csv'),
    ('v_top_dishes', 'top_dishes.csv'),
    ('v_allergen_warnings', 'allergen_warnings.csv'),
    ('v_customer_order_history', 'customer_history.csv'),
    ('v_customer_rfm', 'customer_rfm.csv'),
    ('v_monthly_revenue_trends', 'monthly_revenue_trends.csv'),
    ('v_hourly_demand_patterns', 'hourly_demand.csv'),
    ('v_source_performance', 'source_performance.csv'),
    ('v_kitchen_efficiency', 'kitchen_efficiency.csv'),
    ('v_vat_breakdown_monthly', 'vat_breakdown.csv'),
    ('v_customer_behavior', 'customer_behavior.csv'),
    ('v_revenue_forecast', 'revenue_forecast.csv'),
    ('v_top_customers', 'top_customers.csv'),
    ('v_lunch_vs_dinner_analysis', 'lunch_vs_dinner.csv'),
    ('v_order_summary', 'order_summary.csv'),
]

# Tables to export
TABLES_TO_EXPORT = [
    ('Employees', 'employees.csv'),
    ('Users', 'users.csv'),
    ('Menus', 'menus.csv'),
    ('Orders', 'orders.csv'),
    ('OrderDetails', 'order_details.csv'),
    ('Payments', 'payments.csv'),
    ('Events', 'events.csv'),
    ('Reservations', 'reservations.csv'),
    ('RestaurantTables', 'tables.csv'),
    ('Inventory', 'inventory.csv'),
    ('Allergens', 'allergens.csv'),
    ('MenuAllergens', 'menu_allergens.csv'),
]


def get_connection():
    """Create database connection."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except psycopg2.Error as e:
        print(f"Error connecting to database: {e}")
        print("Make sure PostgreSQL is running and credentials are correct.")
        sys.exit(1)


def export_table(conn, table_name, output_file):
    """Export a table to CSV."""
    cursor = conn.cursor()
    try:
        cursor.execute(f"SELECT * FROM {table_name}")
        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]

        filepath = os.path.join(OUTPUT_DIR, output_file)
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(columns)
            writer.writerows(rows)

        print(f"  [OK] {table_name} -> {output_file} ({len(rows)} rows)")
        return len(rows)
    except Exception as e:
        print(f"  [FAIL] {table_name}: {e}")
        return 0
    finally:
        cursor.close()


def export_view(conn, view_name, output_file):
    """Export a view to CSV."""
    cursor = conn.cursor()
    try:
        cursor.execute(f"SELECT * FROM {view_name}")
        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]

        filepath = os.path.join(OUTPUT_DIR, output_file)
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(columns)
            writer.writerows(rows)

        print(f"  [OK] {view_name} -> {output_file} ({len(rows)} rows)")
        return len(rows)
    except Exception as e:
        print(f"  [FAIL] {view_name}: {e}")
        return 0
    finally:
        cursor.close()


def export_summary_stats(conn):
    """Export summary statistics as JSON-like text."""
    cursor = conn.cursor()
    stats = {}

    try:
        # Total revenue
        cursor.execute("SELECT SUM(total) FROM Orders WHERE status = 'completed'")
        stats['total_revenue_czk'] = cursor.fetchone()[0]

        # Total orders
        cursor.execute("SELECT COUNT(*) FROM Orders")
        stats['total_orders'] = cursor.fetchone()[0]

        # Completed orders
        cursor.execute("SELECT COUNT(*) FROM Orders WHERE status = 'completed'")
        stats['completed_orders'] = cursor.fetchone()[0]

        # Unique customers
        cursor.execute("SELECT COUNT(DISTINCT user_id) FROM Orders WHERE status = 'completed'")
        stats['unique_customers'] = cursor.fetchone()[0]

        # Avg order value
        cursor.execute("SELECT AVG(total) FROM Orders WHERE status = 'completed'")
        stats['avg_order_value_czk'] = round(cursor.fetchone()[0], 2)

        # Top dish
        cursor.execute("SELECT name_en, portions_sold FROM v_top_dishes LIMIT 1")
        result = cursor.fetchone()
        if result:
            stats['top_dish'] = result[0]
            stats['top_dish_portions'] = result[1]

        # VAT collected
        cursor.execute("SELECT SUM(vat_amount) FROM Orders WHERE status = 'completed'")
        stats['total_vat_czk'] = cursor.fetchone()[0]

    except Exception as e:
        print(f"  [FAIL] Summary stats: {e}")

    # Write stats file
    filepath = os.path.join(OUTPUT_DIR, 'summary_stats.txt')
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(f"=== Golden Dragon Prague - Export Summary ===\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Database:  golden_dragon_prague\n\n")
        for key, value in stats.items():
            if value is not None:
                f.write(f"{key}: {value}\n")

    print(f"  [OK] summary_stats.txt generated")
    cursor.close()


def main():
    print("=" * 60)
    print("Golden Dragon Prague - Data Export")
    print("=" * 60)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    conn = get_connection()
    print(f"Connected to database: {DB_CONFIG['dbname']}")
    print()

    total_rows = 0

    # Export tables
    print("Exporting tables...")
    for table_name, filename in TABLES_TO_EXPORT:
        total_rows += export_table(conn, table_name, filename)
    print()

    # Export views
    print("Exporting views...")
    for view_name, filename in VIEWS_TO_EXPORT:
        total_rows += export_view(conn, view_name, filename)
    print()

    # Export summary stats
    print("Generating summary statistics...")
    export_summary_stats(conn)
    print()

    conn.close()

    print("=" * 60)
    print(f"Export complete! {total_rows} total rows exported.")
    print(f"Files saved to: {OUTPUT_DIR}")
    print("=" * 60)


if __name__ == '__main__':
    main()
