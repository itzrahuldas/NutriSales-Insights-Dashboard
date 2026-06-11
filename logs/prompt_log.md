# 📓 NutriSales Insights — Prompt Log

> This file documents every decision made during this project — what we did, why we did it, and what it means for interviews.

---

## 🗓️ Session 1 — Environment Setup & Project Scaffold

### What we did
- Checked Python (3.11.9), pip, Git (2.52), Node versions
- Created project folder: `nutrisales-insights-dashboard/`
- Set up subdirectories: `data/`, `notebooks/`, `sql/`, `outputs/`, `dashboard/`, `logs/`
- Installed packages: pandas, matplotlib, seaborn, plotly, openpyxl, jupyter, nbconvert

### Why this structure?
Each folder maps to a phase of the analytics workflow:
- `data/` → raw + clean files (gitignored for size)
- `notebooks/` → reproducible Python analysis
- `sql/` → standalone queries any analyst can run
- `outputs/` → chart PNGs for README/dashboard
- `dashboard/` → Power BI file
- `logs/` → documentation trail (this file!)

### Interview answer prep
> "I structured the project like a real analytics team's repository — separating raw data, transformation logic, SQL queries, and output artifacts. This makes it easy for another analyst to pick up the project."

---

## 🗓️ Session 2 — Data Download & Cleaning

### Dataset: UCI Online Retail
- Source: https://archive.ics.uci.edu/static/public/352/online+retail.zip
- Raw shape: 541,909 rows x 8 columns
- Format: Excel (.xlsx) → converted to CSV

### Cleaning decisions (and WHY each one matters)

| Decision | Code | Interview Explanation |
|----------|------|-----------------------|
| Drop missing `CustomerID` | `df.dropna(subset=['CustomerID'])` | Can't track retention without knowing who bought. These rows are anonymous purchases — useless for cohort analysis. |
| Remove cancellations | `~df['InvoiceNo'].str.startswith('C')` | Invoices prefixed with 'C' are returns/refunds. Including them would show negative revenue in some months — data corruption. |
| Remove bad quantities | `df[(df['Quantity'] > 0) & (df['UnitPrice'] > 0)]` | Negative quantities = returns already captured. Zero prices = test entries or giveaways. Both corrupt revenue calculations. |
| Currency Conversion | `df['UnitPrice'] * 105` | The target demographic analysis requires Indian context, so GBP was converted to INR at ~105 rate. |
| Create `Revenue` column | `df['Quantity'] * df['UnitPrice']` | Raw data has no revenue column. We engineer it from the two atomic fields. This is called **feature engineering**. |
| Parse `InvoiceDate` | `pd.to_datetime(df['InvoiceDate'])` | String dates can't be grouped by month/year or used in time-series. Converting to datetime unlocks `.dt` accessor. |
| Extract `Month`, `Hour`, `DayOfWeek` | `.dt.to_period('M')`, `.dt.hour`, `.dt.day_name()` | These derived columns power the heatmap and monthly trend — we're decomposing a timestamp into its components. |

### Expected clean row count
Starting 541,909 → After cleaning: 397,884 rows.

---

## 🗓️ Session 3 — Python EDA Charts

### Chart 1: Monthly Revenue Trend (dual-axis)
**File**: `outputs/monthly_revenue.png`

- Left Y-axis: Monthly revenue (INR) as a filled line chart
- Right Y-axis: MoM Growth % as transparent bars (green = positive, red = negative)
- Why dual-axis? Tells two stories on one chart — absolute revenue AND rate of change

**Interview insight**: "November 2011 showed the highest MoM spike — this is consistent with holiday shopping behaviour. I would recommend the marketing team pre-position ad spend in October to capture this demand."

### Chart 2: Top 10 Products by Revenue
**File**: `outputs/top_products.png`

- Horizontal bar chart (easier to read long product names)
- Sorted descending — hero SKU is immediately visible
- Revenue labels on each bar for instant reading

**Interview insight**: "The top product contributed significantly to total revenue. This concentration risk means we should develop complementary products or bundles to reduce dependency."

### Chart 3: Revenue by Country (Interactive HTML)
**File**: `outputs/country_revenue.html`

- Plotly interactive — hover shows customers + orders + share %
- Reveals that the UK dominates (expected for a UK retailer)
- NETHERLANDS, EIRE, GERMANY rank 2nd–4th

**Interview insight**: "85%+ revenue from one geography is a concentration risk. If UK demand softens, the business has limited diversification. I'd recommend testing localised marketing in top 3 European countries."

### Chart 4: Revenue Heatmap (Day × Hour)
**File**: `outputs/heatmap.png`

- Rows = day of week, Columns = hour (0–23)
- YlOrRd colour scale — dark red = peak revenue hour
- Reveals: most sales happen Tuesday–Thursday, 10am–3pm

**Interview insight**: "Revenue peaks on weekday mid-days. Email campaigns and paid ads should be scheduled for Tuesday–Thursday 10am for maximum engagement."

---

## 🗓️ Session 4 — SQL KPI Queries

### Window functions used
```sql
LAG(total_revenue) OVER (ORDER BY month)
```
**What is LAG()?** A window function that returns the value from the *previous row* in the result set, ordered by a specific column. We use it to compare this month's revenue to last month's — enabling MoM growth calculation without a self-join.

**Interview script**: "I used `LAG()` as a window function to compute month-over-month growth. The window is ordered by month, so each row sees the previous month's revenue. I then compute `(current - previous) / previous × 100` for the growth percentage."

### CTE (Common Table Expression) usage
```sql
WITH first_purchase AS (...),
     customer_months AS (...)
SELECT ... FROM customer_months
```
**What is a CTE?** A named temporary result set that exists for the duration of a query. It makes complex logic readable — like creating a named variable in SQL.

**Interview script**: "I used two CTEs for the retention query. The first finds each customer's cohort month (their first ever purchase). The second joins this back to all purchases, so I can check which customers returned in months after their cohort month."

### Anomaly detection with Z-Score
```sql
ROUND((total_revenue - mean_rev) / stddev_rev, 2) AS z_score
```
**What is Z-score?** Measures how many standard deviations a data point is from the mean. |Z| > 2 = statistically anomalous. SQLite has no `STDDEV()` function, so we compute it manually using `SQRT(AVG(x²) - AVG(x)²)`.

---

## 🗓️ Session 5 — Power BI Dashboard

### Data connection strategy
- Load `data/clean_retail.csv` via **Get Data → Text/CSV**
- This is the simplest approach — no ODBC driver needed
- For production: connect directly to SQLite via `System DSN`

### DAX measures explained

```dax
Total Revenue = SUM(sales[Revenue])
```
Simple aggregation — sums the Revenue column across all rows in the current filter context.

```dax
AOV = DIVIDE([Total Revenue], [Total Orders])
```
`DIVIDE()` instead of `/` — handles division by zero gracefully (returns BLANK instead of error).

```dax
MoM Growth % =
VAR CurrentMonthRev = [Total Revenue]
VAR PrevMonthRev = CALCULATE([Total Revenue], DATEADD('sales'[InvoiceDate], -1, MONTH))
RETURN DIVIDE(CurrentMonthRev - PrevMonthRev, PrevMonthRev)
```
`DATEADD(..., -1, MONTH)` shifts the filter context back 1 month. `CALCULATE()` re-evaluates `[Total Revenue]` in this shifted context. This is the Power BI equivalent of SQL's `LAG()`.

**Interview script**: "In Power BI, time intelligence functions like `DATEADD()` require a proper Date table marked as such. I used `CALCULATE()` to override the filter context — this is one of the most powerful concepts in DAX."

---

## 📊 Key Findings

| Metric | Value |
|--------|-------|
| Total Revenue | INR 935,697,829.92 (~93.5 Cr) |
| Total Orders | 18,532 |
| Average Order Value | INR 50,490.92 |
| Unique Customers | 4,338 |
| Overall Retention Rate | 65.5% |
| Peak Revenue Month | November 2011 |
| Highest MoM Growth | 47.65% in Nov 2011 |

---

## 🎤 Interview Q&A Ready

**Q: "Walk me through your data cleaning process"**
> "First I identified three main data quality issues: 12% of rows had no CustomerID, which I dropped because retention analysis requires customer identity. About 2% of invoices were cancellations — prefixed with 'C' — which I filtered out to avoid negative revenue. Finally I removed ~1% of rows with zero or negative quantities and prices which were data entry errors. This reduced the dataset from 541K to 397K rows. I also converted the GBP currency to INR (multiplier 105) to align with our local market context."

**Q: "What is a window function?"**
> "A window function performs a calculation across a set of rows related to the current row, without collapsing them into a single output row. I used `LAG()` — which accesses the previous row's value — to calculate month-over-month revenue growth. The `OVER (ORDER BY month)` clause defines the window ordering."

**Q: "What surprised you most in this analysis?"**
> "The geographic concentration was massive — the UK accounted for over 80% of revenue, but the Netherlands and EIRE generated the highest average order values outside the UK. It suggests our wholesale B2B customers are clustered in those regions."

**Q: "How did you handle the SQL without a server?"**
> "I loaded the cleaned pandas DataFrame directly into SQLite using `df.to_sql()`. SQLite is serverless and file-based, which makes it perfect for portfolio projects — no installation or credentials required. All 7 queries use standard SQL-92 syntax with two SQLite-specific adaptations: `strftime()` instead of `DATE_TRUNC()`, and manual STDDEV calculation since SQLite lacks an aggregate STDDEV function."
