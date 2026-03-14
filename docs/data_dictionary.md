# Data Dictionary — Retail Analytics Lakehouse

**Project:** Microsoft Fabric Retail Analytics Pipeline  
**Author:** Koteesh Vijayasekar Thugundram  
**Last Updated:** March 2026  
**Lakehouse:** RetailLakehouse (Microsoft Fabric)

---

## Overview

This data dictionary documents all tables across the three Medallion layers of the RetailLakehouse. The pipeline processes the Online Retail II dataset (UCI Machine Learning Repository) — real UK e-commerce transactions spanning 2009–2011.

| Layer | Format | Tables | Description |
|-------|--------|--------|-------------|
| Bronze | CSV | `online_retail_raw` | Raw source data, unmodified |
| Silver | Delta (partitioned) | `retail_transactions` | Cleaned and standardised |
| Gold | Delta (managed) | `fact_sales`, `dim_customer`, `dim_product`, `dim_date` | Star schema for analytics |

---

## Bronze Layer

### `online_retail_raw` (Files/bronze/online_retail_raw.csv)

Raw source file. Never modified. Preserved as the audit trail.

| Column | Type | Example | Description |
|--------|------|---------|-------------|
| InvoiceNo | string | `536365` | Unique invoice identifier. Values starting with `C` indicate cancellations. |
| StockCode | string | `85123A` | Product/item code assigned by the retailer. |
| Description | string | `WHITE HANGING HEART T-LIGHT HOLDER` | Product description. May contain nulls or inconsistent casing. |
| Quantity | integer | `6` | Units purchased per line item. Negative values indicate returns. |
| InvoiceDate | string | `12/1/2010 8:26` | Date and time of transaction. Raw format: `M/d/yyyy H:mm`. |
| UnitPrice | float | `2.55` | Price per unit in GBP (£). |
| CustomerID | float | `17850.0` | Numeric customer identifier. Nulls present for guest transactions. |
| Country | string | `United Kingdom` | Country where the customer resides. |

**Known quality issues in raw data:**
- ~25% of rows have null `CustomerID` (guest checkouts) — filtered in Silver
- Cancelled invoices present (prefix `C`) — filtered in Silver
- Negative `Quantity` values for returns — filtered in Silver
- `CustomerID` stored as float (e.g. `17850.0`) — cast to integer in Silver
- `InvoiceDate` stored as string — cast to timestamp in Silver
- Duplicate rows present on `InvoiceNo` + `StockCode` — deduplicated in Silver

---

## Silver Layer

### `retail_transactions` (Files/silver/retail_transactions/)

Cleaned, validated, and type-cast version of the Bronze data. Written as Delta format, partitioned by `Country`. One row per invoice line item.

**Filters applied from Bronze:**
- Removed rows where `CustomerID` is null
- Removed cancelled orders (InvoiceNo starting with `C`)
- Removed rows where `Quantity <= 0` or `UnitPrice <= 0`
- Deduplicated on `InvoiceNo` + `StockCode`

| Column | Type | Example | Description |
|--------|------|---------|-------------|
| InvoiceNo | string | `536365` | Invoice identifier. Cancellations excluded. |
| StockCode | string | `85123A` | Product code. |
| Description | string | `WHITE HANGING HEART T-LIGHT HOLDER` | Product description. |
| Quantity | integer | `6` | Units purchased. Guaranteed positive. |
| InvoiceDate | timestamp | `2010-12-01 08:26:00` | Parsed from raw string. Format: `yyyy-MM-dd HH:mm:ss`. |
| UnitPrice | decimal(10,2) | `2.55` | Price per unit in GBP. Guaranteed positive. |
| CustomerID | integer | `17850` | Customer identifier. No nulls. Cast from float. |
| Country | string | `United Kingdom` | Customer country. Used as partition key. |
| LineTotal | decimal(10,2) | `15.30` | Derived: `Quantity × UnitPrice`. |
| ingestion_ts | timestamp | `2026-03-14 06:00:00` | Pipeline run timestamp. Added during transformation. |

**Partition key:** `Country`  
**Reason:** Most analytical queries filter by geography. Partitioning by Country enables partition pruning, reducing scan volume for country-level queries.

---

## Gold Layer

The Gold layer implements a **star schema** — one central fact table surrounded by three dimension tables. All tables are managed Delta tables registered in the Lakehouse SQL analytics endpoint and accessible to Power BI via Direct Lake mode.

---

### `fact_sales`

Grain: one row per invoice line item (one product on one invoice).  
Foreign keys link to all three dimension tables.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| invoice_no | string | No | Invoice identifier. Sourced from `InvoiceNo`. |
| customer_key | integer | Yes | FK → `dim_customer.customer_key`. Surrogate key. |
| product_key | integer | Yes | FK → `dim_product.product_key`. Surrogate key. |
| date_key | integer | Yes | FK → `dim_date.date_key`. Format: `yyyyMMdd` (e.g. `20101201`). |
| quantity | integer | No | Units sold on this line item. |
| unit_price | decimal(10,2) | No | Price per unit at time of sale in GBP. |
| line_total | decimal(10,2) | No | `quantity × unit_price`. Primary revenue metric. |

**Indexes (Azure SQL / Fabric Warehouse):**
- `idx_fact_sales_date` on `date_key` — supports time-based slicing
- `idx_fact_sales_customer` on `customer_key` — supports customer analysis queries

**Approximate row count:** ~400,000 (after Silver filtering)

---

### `dim_customer`

One row per unique customer. Sourced from distinct `CustomerID` + `Country` combinations in Silver.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| customer_key | integer | No | **Primary key.** Surrogate key generated via `row_number()` ordered by `CustomerID`. |
| CustomerID | integer | No | Natural key from source system. |
| Country | string | Yes | Customer's country of residence. |

**Approximate row count:** ~4,300 unique customers

---

### `dim_product`

One row per unique product. Sourced from distinct `StockCode` + `Description` combinations in Silver.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| product_key | integer | No | **Primary key.** Surrogate key generated via `row_number()` ordered by `StockCode`. |
| StockCode | string | No | Natural key. Retailer-assigned product code. |
| Description | string | Yes | Product description. May occasionally be null for unlisted items. |

**Approximate row count:** ~3,900 unique products  
**Note:** Some `StockCode` values are non-standard (e.g. `POST`, `DOT`, `AMAZONFEE`) representing shipping charges and fees rather than physical products. These are retained in the dimension but can be excluded in analytical queries using `WHERE StockCode NOT IN ('POST', 'DOT', 'AMAZONFEE', 'BANK CHARGES')`.

---

### `dim_date`

One row per unique calendar date present in the transactions data. Covers 2009–2011.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| date_key | integer | No | **Primary key.** Format: `yyyyMMdd` (e.g. `20101201`). Integer for fast joining. |
| date | date | No | Calendar date. |
| year | integer | No | Calendar year (e.g. `2010`). |
| month | integer | No | Month number 1–12. Use this column to sort `month_name` in Power BI. |
| month_name | string | No | Full month name (e.g. `December`). Sort by `month` in Power BI model view. |
| quarter | integer | No | Quarter number 1–4. |
| day | integer | No | Day of month 1–31. |
| weekday | integer | No | Day of week 1–7. 1 = Sunday, 7 = Saturday (Spark default). |

**Power BI note:** To display months in chronological order, go to Model view → select `month_name` column → Sort by column → select `month`. Without this, months sort alphabetically (April, August, December...).

---

## Key Metrics & Derived Measures

These are not stored columns — they are DAX measures defined in the Power BI semantic model.

| Measure | DAX | Description |
|---------|-----|-------------|
| Total Revenue | `SUMX(fact_sales, fact_sales[quantity] * fact_sales[unit_price])` | Sum of all line totals |
| Total Orders | `DISTINCTCOUNT(fact_sales[invoice_no])` | Count of unique invoices |
| Avg Order Value | `DIVIDE([Total Revenue], [Total Orders])` | Revenue per order |
| Unique Customers | `DISTINCTCOUNT(fact_sales[customer_key])` | Count of distinct customers |
| Revenue MoM % | See implementation guide | Month-over-month revenue change |

---

## Pipeline Lineage

```
online_retail_raw.csv  (Bronze)
        │
        │  01_bronze_to_silver.ipynb
        │  • Filter nulls, cancellations, negatives
        │  • Cast types, derive LineTotal
        │  • Deduplicate, add ingestion_ts
        │  • Write Delta partitioned by Country
        ▼
retail_transactions  (Silver)
        │
        │  02_silver_to_gold.ipynb
        │  • Build dim_customer (distinct CustomerID + Country)
        │  • Build dim_product (distinct StockCode + Description)
        │  • Build dim_date (distinct dates + calendar attributes)
        │  • Build fact_sales (join silver to dimension keys)
        │  • Write as managed Delta tables
        ▼
fact_sales + dim_customer + dim_product + dim_date  (Gold)
        │
        │  Power BI Direct Lake
        ▼
Retail Analytics Dashboard
```

