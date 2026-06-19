-- ============================================================
--  SALES PERFORMANCE DASHBOARD — SQL QUERIES
--  Project : Sales Performance Dashboard (Power BI)
--  Author  : Data Analytics Team
--  Created : 2026
--  Database: sales_performance_db
-- ============================================================


-- ============================================================
-- 0. DATABASE & TABLE SETUP
-- ============================================================

CREATE DATABASE IF NOT EXISTS sales_performance_db;
USE sales_performance_db;

-- Drop table if re-running
DROP TABLE IF EXISTS sales_data;

CREATE TABLE sales_data (
    order_id          VARCHAR(20)    PRIMARY KEY,
    order_date        DATE           NOT NULL,
    customer_id       VARCHAR(20)    NOT NULL,
    customer_name     VARCHAR(100)   NOT NULL,
    product_id        VARCHAR(20)    NOT NULL,
    product_name      VARCHAR(150)   NOT NULL,
    category          VARCHAR(50)    NOT NULL,
    sub_category      VARCHAR(50)    NOT NULL,
    region            VARCHAR(50)    NOT NULL,
    country           VARCHAR(50)    NOT NULL,
    state             VARCHAR(50)    NOT NULL,
    city              VARCHAR(100)   NOT NULL,
    sales_amount      DECIMAL(12,2)  NOT NULL,
    quantity_sold     INT            NOT NULL,
    unit_price        DECIMAL(10,2)  NOT NULL,
    cost_price        DECIMAL(10,2)  NOT NULL,
    profit            DECIMAL(12,2)  NOT NULL,
    discount          DECIMAL(5,2)   NOT NULL DEFAULT 0.00,
    payment_method    VARCHAR(30)    NOT NULL,
    sales_rep         VARCHAR(100)   NOT NULL,
    -- Derived columns (populated by UPDATE or generated columns)
    profit_margin     DECIMAL(8,4)   GENERATED ALWAYS AS
                          (CASE WHEN sales_amount = 0 THEN 0
                                ELSE (profit / sales_amount) * 100 END) STORED,
    sales_status      VARCHAR(20)    NOT NULL DEFAULT 'Unknown'
);

-- Index for common filter columns
CREATE INDEX idx_order_date   ON sales_data(order_date);
CREATE INDEX idx_region        ON sales_data(region);
CREATE INDEX idx_category      ON sales_data(category);
CREATE INDEX idx_product_id    ON sales_data(product_id);
CREATE INDEX idx_customer_id   ON sales_data(customer_id);
CREATE INDEX idx_sales_rep     ON sales_data(sales_rep);


-- ============================================================
-- 1. DATA CLEANING QUERIES
-- ============================================================

-- 1a. Check for duplicate Order IDs
-- Explanation: Identifies orders appearing more than once so duplicates
--              can be removed before any analysis is performed.
SELECT
    order_id,
    COUNT(*) AS duplicate_count
FROM sales_data
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;


-- 1b. Remove duplicate records (keep the first occurrence)
-- Explanation: Deletes all duplicate rows keeping only the row with the
--              lowest internal row number for each order_id.
DELETE s1
FROM sales_data s1
INNER JOIN sales_data s2
    ON s1.order_id = s2.order_id
   AND s1.rowid    > s2.rowid;          -- MySQL syntax; use ctid in PostgreSQL


-- 1c. Handle missing / NULL values — flag rows for review
-- Explanation: Returns every record that has at least one critical NULL
--              so data-quality issues can be corrected at the source.
SELECT *
FROM sales_data
WHERE order_id       IS NULL
   OR order_date     IS NULL
   OR customer_id    IS NULL
   OR product_id     IS NULL
   OR sales_amount   IS NULL
   OR region         IS NULL;


-- 1d. Standardise category names (fix common inconsistencies)
-- Explanation: Normalises free-text category values so groupings work
--              correctly in visualisations.
UPDATE sales_data
SET category = CASE
    WHEN LOWER(TRIM(category)) IN ('tech', 'technology', 'tech.')         THEN 'Technology'
    WHEN LOWER(TRIM(category)) IN ('furn', 'furniture', 'furnishings')    THEN 'Furniture'
    WHEN LOWER(TRIM(category)) IN ('off sup', 'office sup', 'office supplies') THEN 'Office Supplies'
    WHEN LOWER(TRIM(category)) IN ('apparel', 'clothing', 'clothes')      THEN 'Clothing'
    WHEN LOWER(TRIM(category)) IN ('elec', 'electronics', 'electronic')   THEN 'Electronics'
    ELSE TRIM(category)
END;


-- 1e. Update Sales Status column
-- Explanation: Classifies each order into a business-meaningful status
--              band based on the order's sales amount.
UPDATE sales_data
SET sales_status = CASE
    WHEN sales_amount >= 5000 THEN 'High Value'
    WHEN sales_amount >= 1000 THEN 'Medium Value'
    WHEN sales_amount >= 100  THEN 'Low Value'
    ELSE 'Micro'
END;


-- 1f. Add derived date columns (Month, Quarter, Year)
-- Explanation: Adds time-intelligence columns used by the dashboard
--              slicers and trend charts.
ALTER TABLE sales_data
    ADD COLUMN order_year    SMALLINT  GENERATED ALWAYS AS (YEAR(order_date))  STORED,
    ADD COLUMN order_quarter TINYINT   GENERATED ALWAYS AS (QUARTER(order_date)) STORED,
    ADD COLUMN order_month   TINYINT   GENERATED ALWAYS AS (MONTH(order_date)) STORED,
    ADD COLUMN month_name    VARCHAR(9) GENERATED ALWAYS AS
        (MONTHNAME(order_date)) STORED;


-- ============================================================
-- 2. TOTAL SALES BY REGION
-- ============================================================
-- Explanation: Summarises revenue, profit, order count and average
--              order value for every region, ordered by highest revenue.
--              This feeds the Regional Performance map and KPI cards.
SELECT
    region,
    COUNT(DISTINCT order_id)                                AS total_orders,
    COUNT(DISTINCT customer_id)                             AS total_customers,
    ROUND(SUM(sales_amount),       2)                       AS total_revenue,
    ROUND(SUM(profit),             2)                       AS total_profit,
    ROUND(AVG(sales_amount),       2)                       AS avg_order_value,
    ROUND(SUM(profit) / NULLIF(SUM(sales_amount), 0) * 100, 2) AS profit_margin_pct,
    ROUND(SUM(quantity_sold),      0)                       AS total_units_sold
FROM sales_data
GROUP BY region
ORDER BY total_revenue DESC;


-- ============================================================
-- 3. TOP 10 PRODUCTS BY REVENUE
-- ============================================================
-- Explanation: Returns the ten best-selling products ranked by total
--              revenue. Used in the horizontal bar chart visual.
SELECT
    product_id,
    product_name,
    category,
    sub_category,
    ROUND(SUM(sales_amount),  2)  AS total_revenue,
    ROUND(SUM(profit),        2)  AS total_profit,
    SUM(quantity_sold)            AS total_units_sold,
    ROUND(AVG(discount) * 100, 2) AS avg_discount_pct,
    DENSE_RANK() OVER (ORDER BY SUM(sales_amount) DESC) AS revenue_rank
FROM sales_data
GROUP BY product_id, product_name, category, sub_category
ORDER BY total_revenue DESC
LIMIT 10;


-- ============================================================
-- 4. MONTHLY REVENUE TRENDS
-- ============================================================
-- Explanation: Aggregates revenue and profit month-by-month so the line
--              chart can show seasonality and growth patterns over time.
SELECT
    order_year                                          AS yr,
    order_month                                         AS mth,
    month_name,
    CONCAT(order_year, '-', LPAD(order_month, 2, '0')) AS year_month,
    COUNT(DISTINCT order_id)                            AS total_orders,
    ROUND(SUM(sales_amount), 2)                         AS monthly_revenue,
    ROUND(SUM(profit),       2)                         AS monthly_profit,
    ROUND(
        (SUM(sales_amount) - LAG(SUM(sales_amount))
            OVER (ORDER BY order_year, order_month))
        / NULLIF(LAG(SUM(sales_amount))
            OVER (ORDER BY order_year, order_month), 0) * 100
    , 2)                                                AS mom_growth_pct
FROM sales_data
GROUP BY order_year, order_month, month_name
ORDER BY order_year, order_month;


-- ============================================================
-- 5. CATEGORY-WISE SALES
-- ============================================================
-- Explanation: Breaks revenue and profit down by category and
--              sub-category for the bar chart and treemap visuals.
SELECT
    category,
    sub_category,
    COUNT(DISTINCT order_id)                                     AS total_orders,
    ROUND(SUM(sales_amount), 2)                                  AS total_revenue,
    ROUND(SUM(profit),       2)                                  AS total_profit,
    SUM(quantity_sold)                                           AS total_units,
    ROUND(SUM(profit) / NULLIF(SUM(sales_amount), 0) * 100, 2)  AS profit_margin_pct,
    ROUND(SUM(sales_amount) /
        (SELECT SUM(sales_amount) FROM sales_data) * 100, 2)    AS revenue_share_pct
FROM sales_data
GROUP BY category, sub_category
ORDER BY category, total_revenue DESC;


-- ============================================================
-- 6. CUSTOMER SEGMENTATION (RFM-BASED)
-- ============================================================
-- Explanation: Calculates Recency, Frequency and Monetary (RFM) values
--              for every customer, then assigns a segment label.
--              This drives the donut chart and customer analysis page.

WITH rfm_raw AS (
    SELECT
        customer_id,
        customer_name,
        DATEDIFF(
            (SELECT MAX(order_date) FROM sales_data),
            MAX(order_date)
        )                              AS recency_days,
        COUNT(DISTINCT order_id)       AS frequency,
        ROUND(SUM(sales_amount), 2)    AS monetary
    FROM sales_data
    GROUP BY customer_id, customer_name
),
rfm_scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,   -- lower = more recent
        NTILE(5) OVER (ORDER BY frequency    DESC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary     DESC) AS m_score
    FROM rfm_raw
)
SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    monetary,
    r_score, f_score, m_score,
    (r_score + f_score + m_score)     AS rfm_total,
    CASE
        WHEN (r_score + f_score + m_score) >= 13 THEN 'Champions'
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Loyal Customers'
        WHEN (r_score + f_score + m_score) >= 7  THEN 'Potential Loyalists'
        WHEN (r_score + f_score + m_score) >= 5  THEN 'At-Risk Customers'
        ELSE                                           'Lost Customers'
    END AS customer_segment
FROM rfm_scored
ORDER BY rfm_total DESC;


-- ============================================================
-- 7. AVERAGE ORDER VALUE (AOV)
-- ============================================================
-- Explanation: Provides overall and region-level AOV metrics used in
--              KPI cards and executive summary.
SELECT
    region,
    COUNT(DISTINCT order_id)        AS total_orders,
    ROUND(SUM(sales_amount),  2)    AS total_revenue,
    ROUND(AVG(sales_amount),  2)    AS avg_order_value,
    ROUND(MIN(sales_amount),  2)    AS min_order_value,
    ROUND(MAX(sales_amount),  2)    AS max_order_value,
    ROUND(STDDEV(sales_amount), 2)  AS stddev_order_value
FROM sales_data
GROUP BY region

UNION ALL

SELECT
    'ALL REGIONS'                   AS region,
    COUNT(DISTINCT order_id),
    ROUND(SUM(sales_amount),  2),
    ROUND(AVG(sales_amount),  2),
    ROUND(MIN(sales_amount),  2),
    ROUND(MAX(sales_amount),  2),
    ROUND(STDDEV(sales_amount), 2)
FROM sales_data
ORDER BY region;


-- ============================================================
-- 8. PROFITABILITY ANALYSIS
-- ============================================================
-- Explanation: Scatter-plot data — returns every product's total sales
--              versus total profit so outliers and loss-makers are visible.
SELECT
    product_id,
    product_name,
    category,
    region,
    ROUND(SUM(sales_amount), 2)                                  AS total_revenue,
    ROUND(SUM(profit),       2)                                  AS total_profit,
    ROUND(SUM(profit) / NULLIF(SUM(sales_amount), 0) * 100, 2)  AS profit_margin_pct,
    SUM(quantity_sold)                                           AS total_units,
    ROUND(AVG(discount) * 100, 2)                                AS avg_discount_pct,
    CASE
        WHEN SUM(profit) / NULLIF(SUM(sales_amount), 0) >= 0.30 THEN 'High Margin'
        WHEN SUM(profit) / NULLIF(SUM(sales_amount), 0) >= 0.15 THEN 'Medium Margin'
        WHEN SUM(profit) / NULLIF(SUM(sales_amount), 0) >= 0    THEN 'Low Margin'
        ELSE 'Negative Margin'
    END AS margin_category
FROM sales_data
GROUP BY product_id, product_name, category, region
ORDER BY total_revenue DESC;


-- ============================================================
-- 9. YEAR-OVER-YEAR GROWTH
-- ============================================================
-- Explanation: Compares current-year metrics against the previous year
--              to calculate YoY growth percentages shown in KPI cards.
WITH yearly AS (
    SELECT
        order_year,
        ROUND(SUM(sales_amount), 2)  AS annual_revenue,
        ROUND(SUM(profit),       2)  AS annual_profit,
        COUNT(DISTINCT order_id)     AS total_orders,
        COUNT(DISTINCT customer_id)  AS total_customers
    FROM sales_data
    GROUP BY order_year
)
SELECT
    curr.order_year,
    curr.annual_revenue,
    curr.annual_profit,
    curr.total_orders,
    curr.total_customers,
    prev.annual_revenue                                           AS prev_year_revenue,
    prev.annual_profit                                            AS prev_year_profit,
    ROUND(
        (curr.annual_revenue - prev.annual_revenue)
        / NULLIF(prev.annual_revenue, 0) * 100, 2)              AS yoy_revenue_growth_pct,
    ROUND(
        (curr.annual_profit  - prev.annual_profit)
        / NULLIF(prev.annual_profit,  0) * 100, 2)              AS yoy_profit_growth_pct,
    ROUND(
        (curr.total_orders   - prev.total_orders)
        / NULLIF(prev.total_orders,   0) * 100, 2)              AS yoy_orders_growth_pct
FROM yearly curr
LEFT JOIN yearly prev
    ON curr.order_year = prev.order_year + 1
ORDER BY curr.order_year;


-- ============================================================
-- 10. SALES REPRESENTATIVE PERFORMANCE
-- ============================================================
-- Explanation: Leaderboard of sales reps ranked by revenue.
--              Useful for the Sales Rep drillthrough page.
SELECT
    sales_rep,
    region,
    COUNT(DISTINCT order_id)                                     AS total_orders,
    COUNT(DISTINCT customer_id)                                  AS total_customers,
    ROUND(SUM(sales_amount),  2)                                 AS total_revenue,
    ROUND(SUM(profit),        2)                                 AS total_profit,
    ROUND(AVG(sales_amount),  2)                                 AS avg_order_value,
    ROUND(SUM(profit) / NULLIF(SUM(sales_amount), 0) * 100, 2)  AS profit_margin_pct,
    DENSE_RANK() OVER (ORDER BY SUM(sales_amount) DESC)          AS revenue_rank
FROM sales_data
GROUP BY sales_rep, region
ORDER BY total_revenue DESC;


-- ============================================================
-- 11. PAYMENT METHOD DISTRIBUTION
-- ============================================================
-- Explanation: Counts orders and sums revenue per payment method for
--              the pie chart on the dashboard.
SELECT
    payment_method,
    COUNT(DISTINCT order_id)                                      AS total_orders,
    ROUND(SUM(sales_amount), 2)                                   AS total_revenue,
    ROUND(SUM(sales_amount) /
        (SELECT SUM(sales_amount) FROM sales_data) * 100, 2)     AS revenue_share_pct,
    ROUND(AVG(sales_amount), 2)                                   AS avg_order_value
FROM sales_data
GROUP BY payment_method
ORDER BY total_revenue DESC;


-- ============================================================
-- 12. RUNNING TOTAL SALES (CUMULATIVE)
-- ============================================================
-- Explanation: Computes a running total of revenue ordered by month,
--              used for cumulative trend analysis in reports.
SELECT
    order_year,
    order_month,
    month_name,
    ROUND(SUM(sales_amount), 2)  AS monthly_revenue,
    ROUND(SUM(SUM(sales_amount))
        OVER (
            PARTITION BY order_year
            ORDER BY order_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2)                    AS running_total_revenue,
    ROUND(SUM(SUM(profit))
        OVER (
            PARTITION BY order_year
            ORDER BY order_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2)                    AS running_total_profit
FROM sales_data
GROUP BY order_year, order_month, month_name
ORDER BY order_year, order_month;


-- ============================================================
-- 13. DISCOUNT IMPACT ANALYSIS
-- ============================================================
-- Explanation: Shows how discount levels correlate with profit margin,
--              helping identify where discounts erode profitability.
SELECT
    CASE
        WHEN discount = 0              THEN 'No Discount'
        WHEN discount <= 0.10          THEN '1–10%'
        WHEN discount <= 0.20          THEN '11–20%'
        WHEN discount <= 0.30          THEN '21–30%'
        ELSE                                'Above 30%'
    END                                             AS discount_band,
    COUNT(DISTINCT order_id)                        AS total_orders,
    ROUND(SUM(sales_amount), 2)                     AS total_revenue,
    ROUND(SUM(profit),       2)                     AS total_profit,
    ROUND(AVG(profit_margin), 2)                    AS avg_profit_margin_pct,
    ROUND(AVG(sales_amount),  2)                    AS avg_order_value
FROM sales_data
GROUP BY discount_band
ORDER BY MIN(discount);


-- ============================================================
-- 14. QUARTERLY PERFORMANCE SUMMARY
-- ============================================================
-- Explanation: Aggregates KPIs per quarter for trend comparison and
--              the quarterly drilldown in the dashboard.
SELECT
    order_year,
    order_quarter,
    CONCAT('Q', order_quarter, ' ', order_year)    AS quarter_label,
    COUNT(DISTINCT order_id)                        AS total_orders,
    COUNT(DISTINCT customer_id)                     AS unique_customers,
    ROUND(SUM(sales_amount),  2)                    AS quarterly_revenue,
    ROUND(SUM(profit),        2)                    AS quarterly_profit,
    ROUND(AVG(sales_amount),  2)                    AS avg_order_value,
    ROUND(SUM(profit) / NULLIF(SUM(sales_amount), 0) * 100, 2) AS profit_margin_pct
FROM sales_data
GROUP BY order_year, order_quarter
ORDER BY order_year, order_quarter;


-- ============================================================
-- 15. EXECUTIVE SUMMARY VIEW
-- ============================================================
-- Explanation: Single-row summary of the most important KPIs consumed
--              by the KPI card row at the top of the dashboard.
SELECT
    COUNT(DISTINCT order_id)                                      AS total_orders,
    COUNT(DISTINCT customer_id)                                   AS total_customers,
    COUNT(DISTINCT product_id)                                    AS total_products,
    ROUND(SUM(sales_amount),  2)                                  AS total_revenue,
    ROUND(SUM(profit),        2)                                  AS total_profit,
    ROUND(AVG(sales_amount),  2)                                  AS avg_order_value,
    ROUND(SUM(profit) / NULLIF(SUM(sales_amount), 0) * 100, 2)   AS overall_profit_margin_pct,
    ROUND(AVG(discount) * 100,  2)                                AS avg_discount_pct,
    MIN(order_date)                                               AS first_order_date,
    MAX(order_date)                                               AS last_order_date
FROM sales_data;


-- ============================================================
-- END OF FILE
-- ============================================================
