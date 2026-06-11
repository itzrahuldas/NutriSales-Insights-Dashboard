-- =============================================================
-- NutriSales Insights Dashboard — KPI Queries
-- Database: SQLite (data/retail.db)
-- Run after executing notebooks/01_eda.ipynb to populate DB
-- =============================================================


-- ---------------------------------------------------------------
-- QUERY 1: Monthly Revenue + Month-over-Month (MoM) Growth %
-- WHY: Shows revenue trend and identifies high-growth months.
--      LAG() window function compares current row to previous row
--      ordered by month — this is a classic interview question!
-- ---------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y-%m', InvoiceDate) AS month,
        ROUND(SUM(Revenue), 2)         AS total_revenue
    FROM sales
    GROUP BY month
),
growth AS (
    SELECT
        month,
        total_revenue,
        LAG(total_revenue) OVER (ORDER BY month) AS prev_revenue
    FROM monthly
)
SELECT
    month,
    total_revenue,
    prev_revenue,
    ROUND(
        (total_revenue - prev_revenue) * 100.0 / prev_revenue, 2
    ) AS mom_growth_pct
FROM growth
ORDER BY month;


-- ---------------------------------------------------------------
-- QUERY 2: Average Order Value (AOV)
-- WHY: AOV = Revenue / Orders. Higher AOV = customers spending
--      more per transaction. Key eCommerce health metric.
--      DISTINCTCOUNT on InvoiceNo ensures we count unique orders.
-- ---------------------------------------------------------------
SELECT
    COUNT(DISTINCT InvoiceNo)                          AS total_orders,
    ROUND(SUM(Revenue), 2)                             AS total_revenue,
    ROUND(SUM(Revenue) / COUNT(DISTINCT InvoiceNo), 2) AS avg_order_value
FROM sales;


-- ---------------------------------------------------------------
-- QUERY 3: Customer Cohort Retention Rate
-- WHY: Retention shows how many customers come back after their
--      first purchase month. Uses CTEs to find each customer's
--      cohort (first purchase month) then checks re-purchases.
-- ---------------------------------------------------------------
WITH first_purchase AS (
    SELECT
        CustomerID,
        strftime('%Y-%m', MIN(InvoiceDate)) AS cohort_month
    FROM sales
    GROUP BY CustomerID
),
customer_months AS (
    SELECT DISTINCT
        s.CustomerID,
        strftime('%Y-%m', s.InvoiceDate) AS purchase_month,
        f.cohort_month
    FROM sales s
    JOIN first_purchase f ON s.CustomerID = f.CustomerID
)
SELECT
    cohort_month,
    COUNT(DISTINCT CustomerID)                          AS total_customers,
    COUNT(DISTINCT CASE
        WHEN purchase_month > cohort_month
        THEN CustomerID END)                            AS returning_customers,
    ROUND(
        COUNT(DISTINCT CASE
            WHEN purchase_month > cohort_month
            THEN CustomerID END) * 100.0
        / COUNT(DISTINCT CustomerID), 2
    )                                                   AS retention_rate_pct
FROM customer_months
GROUP BY cohort_month
ORDER BY cohort_month;


-- ---------------------------------------------------------------
-- QUERY 4: Top 10 Products by Revenue
-- WHY: Identifies hero SKUs. Marketing should double down on
--      these in paid ads and email campaigns.
-- ---------------------------------------------------------------
SELECT
    Description                    AS product,
    SUM(Quantity)                  AS units_sold,
    ROUND(SUM(Revenue), 2)         AS total_revenue,
    COUNT(DISTINCT InvoiceNo)      AS order_count,
    ROUND(AVG(UnitPrice), 2)       AS avg_unit_price
FROM sales
GROUP BY Description
ORDER BY total_revenue DESC
LIMIT 10;


-- ---------------------------------------------------------------
-- QUERY 5: Revenue by Country (Top 10)
-- WHY: Identifies geographic concentration risk. If 95%+ of
--      revenue is from one country, that's a business risk.
-- ---------------------------------------------------------------
SELECT
    Country,
    COUNT(DISTINCT CustomerID)     AS unique_customers,
    COUNT(DISTINCT InvoiceNo)      AS total_orders,
    ROUND(SUM(Revenue), 2)         AS total_revenue,
    ROUND(
        SUM(Revenue) * 100.0 /
        (SELECT SUM(Revenue) FROM sales), 2
    )                              AS revenue_share_pct
FROM sales
GROUP BY Country
ORDER BY total_revenue DESC
LIMIT 10;


-- ---------------------------------------------------------------
-- QUERY 6: Monthly Unique Customers
-- WHY: Measures customer acquisition/activity per month.
--      Cross-reference with revenue to see if growth is from
--      new customers or higher spend per customer.
-- ---------------------------------------------------------------
SELECT
    strftime('%Y-%m', InvoiceDate) AS month,
    COUNT(DISTINCT CustomerID)     AS unique_customers,
    COUNT(DISTINCT InvoiceNo)      AS total_orders,
    ROUND(SUM(Revenue), 2)         AS total_revenue,
    ROUND(
        SUM(Revenue) / COUNT(DISTINCT CustomerID), 2
    )                              AS revenue_per_customer
FROM sales
GROUP BY month
ORDER BY month;


-- ---------------------------------------------------------------
-- QUERY 7: Outlier Detection — Monthly Revenue Z-Score
-- WHY: Flags anomalous months. Any month with |Z-score| > 2
--      is statistically abnormal and warrants investigation.
-- ---------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y-%m', InvoiceDate) AS month,
        ROUND(SUM(Revenue), 2)         AS total_revenue
    FROM sales
    GROUP BY month
),
stats AS (
    SELECT
        AVG(total_revenue)                    AS mean_rev,
        -- SQLite has no STDDEV, so we compute it manually
        SQRT(AVG(total_revenue * total_revenue) -
             AVG(total_revenue) * AVG(total_revenue)) AS stddev_rev
    FROM monthly
)
SELECT
    m.month,
    m.total_revenue,
    s.mean_rev,
    s.stddev_rev,
    ROUND(
        (m.total_revenue - s.mean_rev) / NULLIF(s.stddev_rev, 0), 2
    ) AS z_score,
    CASE
        WHEN ABS((m.total_revenue - s.mean_rev) / NULLIF(s.stddev_rev, 0)) > 2
        THEN 'ANOMALY'
        ELSE 'Normal'
    END AS flag
FROM monthly m, stats s
ORDER BY m.month;
