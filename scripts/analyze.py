#!/usr/bin/env python3
"""
Golden Dragon Prague - Analytics Connector
===========================================

Connects to the PostgreSQL database and generates analytics reports.
Demonstrates end-to-end data analysis workflow:
  1. Extract data from database
  2. Analyze with Python (pandas)
  3. Generate insights and visualizations
  4. Export HTML report

Usage:
    python scripts/analyze.py

Output:
    samples/dashboard_output/analytics_report.html

Requirements:
    pip install psycopg2-binary pandas matplotlib seaborn
"""

import os
import sys
import psycopg2
import pandas as pd
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import io
import base64

# Database configuration
DB_CONFIG = {
    'dbname': 'golden_dragon_prague',
    'user': 'postgres',
    'password': 'postgres',
    'host': 'localhost',
    'port': 5432
}

# Output directory
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'samples', 'dashboard_output')

# Color palette (restaurant-themed)
COLORS = {
    'primary': '#C41E3A',    # Chinese red
    'secondary': '#D4A574',  # Golden
    'accent': '#2E8B57',     # Green
    'neutral': '#4A4A4A',    # Dark gray
    'light': '#F5F5DC'       # Beige
}


def get_connection():
    """Create database connection."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except psycopg2.Error as e:
        print(f"Error connecting to database: {e}")
        print("Make sure PostgreSQL is running and credentials are correct.")
        sys.exit(1)


def fig_to_base64(fig):
    """Convert matplotlib figure to base64 for HTML embedding."""
    buf = io.BytesIO()
    fig.savefig(buf, format='png', bbox_inches='tight', dpi=100)
    buf.seek(0)
    img_base64 = base64.b64encode(buf.read()).decode('utf-8')
    plt.close(fig)
    return img_base64


def generate_revenue_chart(df):
    """Generate revenue trend chart."""
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(df['month'].astype(str), df['revenue'], color=COLORS['primary'], alpha=0.8)
    ax.plot(df['month'].astype(str), df['rolling_3mo_avg'], color=COLORS['secondary'], linewidth=2, marker='o', label='3-Month Rolling Avg')
    ax.set_title('Monthly Revenue Trend', fontsize=14, fontweight='bold', color=COLORS['neutral'])
    ax.set_xlabel('Month', fontsize=11)
    ax.set_ylabel('Revenue (CZK)', fontsize=11)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)
    plt.xticks(rotation=45)
    plt.tight_layout()
    return fig_to_base64(fig)


def generate_customer_segment_chart(df):
    """Generate RFM customer segment chart."""
    fig, ax = plt.subplots(figsize=(8, 6))
    segment_counts = df['segment'].value_counts()
    colors = [COLORS['primary'], COLORS['secondary'], COLORS['accent'], '#FF6B6B', '#4ECDC4']
    ax.pie(segment_counts.values, labels=segment_counts.index, autopct='%1.1f%%',
           colors=colors[:len(segment_counts)], startangle=90)
    ax.set_title('Customer Segments (RFM)', fontsize=14, fontweight='bold', color=COLORS['neutral'])
    plt.tight_layout()
    return fig_to_base64(fig)


def generate_source_chart(df):
    """Generate revenue by source chart."""
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.barh(df['source'], df['gross_revenue'], color=COLORS['accent'], alpha=0.8)
    ax.set_title('Revenue by Sales Channel', fontsize=14, fontweight='bold', color=COLORS['neutral'])
    ax.set_xlabel('Revenue (CZK)', fontsize=11)
    ax.grid(axis='x', alpha=0.3)
    plt.tight_layout()
    return fig_to_base64(fig)


def generate_dish_chart(df):
    """Generate top dishes chart."""
    fig, ax = plt.subplots(figsize=(10, 5))
    df_top = df.head(10)
    ax.barh(df_top['name_en'][::-1], df_top['portions_sold'][::-1], color=COLORS['secondary'], alpha=0.8)
    ax.set_title('Top 10 Dishes by Portions Sold', fontsize=14, fontweight='bold', color=COLORS['neutral'])
    ax.set_xlabel('Portions Sold', fontsize=11)
    ax.grid(axis='x', alpha=0.3)
    plt.tight_layout()
    return fig_to_base64(fig)


def generate_hourly_heatmap(df):
    """Generate hourly demand heatmap."""
    pivot = df.pivot_table(values='order_count', index='weekday_name', columns='hour_of_day', aggfunc='sum')
    fig, ax = plt.subplots(figsize=(14, 5))
    sns.heatmap(pivot, annot=True, fmt='g', cmap='YlOrRd', ax=ax, cbar_kws={'label': 'Orders'})
    ax.set_title('Hourly Demand Heatmap (Orders by Day & Hour)', fontsize=14, fontweight='bold', color=COLORS['neutral'])
    ax.set_xlabel('Hour of Day', fontsize=11)
    ax.set_ylabel('Day of Week', fontsize=11)
    plt.tight_layout()
    return fig_to_base64(fig)


def generate_html_report(stats, charts):
    """Generate HTML report with embedded charts."""
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Golden Dragon Prague - Analytics Report</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #f5f5dc 0%, #ffe4c4 100%);
            min-height: 100vh;
            padding: 20px;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
        }}
        header {{
            background: linear-gradient(135deg, #C41E3A 0%, #8B0000 100%);
            color: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            text-align: center;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }}
        header h1 {{
            font-size: 2.2em;
            margin-bottom: 10px;
        }}
        header p {{
            font-size: 1.1em;
            opacity: 0.9;
        }}
        .kpi-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .kpi-card {{
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
            border-top: 4px solid {COLORS['primary']};
        }}
        .kpi-value {{
            font-size: 2em;
            font-weight: bold;
            color: {COLORS['primary']};
            margin: 10px 0;
        }}
        .kpi-label {{
            font-size: 0.9em;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
        }}
        .chart-section {{
            background: white;
            padding: 25px;
            border-radius: 12px;
            margin-bottom: 25px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .chart-section h2 {{
            color: {COLORS['neutral']};
            margin-bottom: 15px;
            font-size: 1.4em;
            border-bottom: 2px solid {COLORS['secondary']};
            padding-bottom: 8px;
        }}
        .chart-section img {{
            width: 100%;
            max-width: 800px;
            margin: 0 auto;
            display: block;
        }}
        .footer {{
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 0.9em;
        }}
        .badge {{
            display: inline-block;
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
            margin: 5px;
        }}
        .badge-primary {{ background: {COLORS['primary']}; color: white; }}
        .badge-secondary {{ background: {COLORS['secondary']}; color: white; }}
        .badge-accent {{ background: {COLORS['accent']}; color: white; }}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Golden Dragon Prague</h1>
            <p>Chinese Restaurant Analytics Dashboard</p>
            <p style="font-size: 0.9em; margin-top: 10px;">Generated: {datetime.now().strftime('%B %d, %Y at %H:%M')}</p>
        </header>

        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-label">Total Revenue</div>
                <div class="kpi-value">{stats.get('total_revenue_czk', 0):,.0f} CZK</div>
                <span class="badge badge-primary">Lifetime</span>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Total Orders</div>
                <div class="kpi-value">{stats.get('total_orders', 0):,}</div>
                <span class="badge badge-secondary">All Time</span>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Avg Order Value</div>
                <div class="kpi-value">{stats.get('avg_order_value_czk', 0):,.0f} CZK</div>
                <span class="badge badge-accent">Completed</span>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Unique Customers</div>
                <div class="kpi-value">{stats.get('unique_customers', 0):,}</div>
                <span class="badge badge-primary">Active</span>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">VAT Collected</div>
                <div class="kpi-value">{stats.get('total_vat_czk', 0):,.0f} CZK</div>
                <span class="badge badge-secondary">12% Rate</span>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Top Dish</div>
                <div class="kpi-value" style="font-size: 1.2em;">{stats.get('top_dish', 'N/A')}</div>
                <span class="badge badge-accent">{stats.get('top_dish_portions', 0)} portions</span>
            </div>
        </div>
"""

    # Add charts
    chart_titles = {
        'revenue': 'Monthly Revenue Trend',
        'customer_segment': 'Customer Segmentation (RFM)',
        'source': 'Revenue by Sales Channel',
        'dish': 'Top 10 Dishes by Volume',
        'hourly': 'Hourly Demand Heatmap',
    }

    for key, title in chart_titles.items():
        if key in charts:
            html += f"""
        <div class="chart-section">
            <h2>{title}</h2>
            <img src="data:image/png;base64,{charts[key]}" alt="{title}">
        </div>
"""

    html += """
        <div class="footer">
            <p>Golden Dragon Prague Database | PostgreSQL 17 | Generated by Analytics Connector</p>
            <p style="margin-top: 5px;">Business: Chinese Restaurant in Prague, Czech Republic</p>
        </div>
    </div>
</body>
</html>
"""
    return html


def main():
    print("=" * 60)
    print("Golden Dragon Prague - Analytics Report Generator")
    print("=" * 60)
    print()

    conn = get_connection()
    print(f"Connected to database: {DB_CONFIG['dbname']}")
    print()

    charts = {}
    stats = {}

    # Generate charts
    print("Generating charts...")

    # 1. Revenue trend
    try:
        df = pd.read_sql("SELECT * FROM v_monthly_revenue_trends ORDER BY month", conn)
        charts['revenue'] = generate_revenue_chart(df)
        print("  [OK] Revenue trend chart")
    except Exception as e:
        print(f"  [FAIL] Revenue chart: {e}")

    # 2. Customer segments
    try:
        df = pd.read_sql("SELECT segment, COUNT(*) as cnt FROM v_customer_rfm GROUP BY segment", conn)
        charts['customer_segment'] = generate_customer_segment_chart(df)
        print("  [OK] Customer segment chart")
    except Exception as e:
        print(f"  [FAIL] Customer segment chart: {e}")

    # 3. Source performance
    try:
        df = pd.read_sql("SELECT source, gross_revenue FROM v_source_performance", conn)
        charts['source'] = generate_source_chart(df)
        print("  [OK] Source performance chart")
    except Exception as e:
        print(f"  [FAIL] Source chart: {e}")

    # 4. Top dishes
    try:
        df = pd.read_sql("SELECT name_en, portions_sold FROM v_top_dishes ORDER BY portions_sold DESC", conn)
        charts['dish'] = generate_dish_chart(df)
        print("  [OK] Top dishes chart")
    except Exception as e:
        print(f"  [FAIL] Top dishes chart: {e}")

    # 5. Hourly heatmap
    try:
        df = pd.read_sql("SELECT * FROM v_hourly_demand_patterns", conn)
        charts['hourly'] = generate_hourly_heatmap(df)
        print("  [OK] Hourly heatmap chart")
    except Exception as e:
        print(f"  [FAIL] Hourly heatmap: {e}")

    print()

    # Collect summary stats
    print("Collecting summary statistics...")
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT SUM(total) FROM Orders WHERE status = 'completed'")
        stats['total_revenue_czk'] = cursor.fetchone()[0] or 0

        cursor.execute("SELECT COUNT(*) FROM Orders")
        stats['total_orders'] = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(DISTINCT user_id) FROM Orders WHERE status = 'completed'")
        stats['unique_customers'] = cursor.fetchone()[0]

        cursor.execute("SELECT AVG(total) FROM Orders WHERE status = 'completed'")
        stats['avg_order_value_czk'] = round(cursor.fetchone()[0] or 0, 2)

        cursor.execute("SELECT SUM(vat_amount) FROM Orders WHERE status = 'completed'")
        stats['total_vat_czk'] = cursor.fetchone()[0] or 0

        cursor.execute("SELECT name_en, portions_sold FROM v_top_dishes LIMIT 1")
        result = cursor.fetchone()
        if result:
            stats['top_dish'] = result[0]
            stats['top_dish_portions'] = result[1]

        print("  [OK] Statistics collected")
    except Exception as e:
        print(f"  [FAIL] Stats: {e}")
    finally:
        cursor.close()

    conn.close()
    print()

    # Generate HTML report
    print("Generating HTML report...")
    html = generate_html_report(stats, charts)

    report_path = os.path.join(OUTPUT_DIR, 'analytics_report.html')
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f"  [OK] Report saved to: {report_path}")
    print()

    print("=" * 60)
    print("Analytics report generation complete!")
    print(f"Open {report_path} in a browser to view the dashboard.")
    print("=" * 60)


if __name__ == '__main__':
    main()
