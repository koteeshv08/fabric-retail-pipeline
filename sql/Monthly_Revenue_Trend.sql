SELECT
    d.year,
    d.month,
    d.month_name,
    SUM(f.line_total)        AS total_revenue,
    COUNT(DISTINCT f.invoice_no) AS total_orders,
    AVG(f.line_total)        AS avg_order_value
FROM fact_sales f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;
