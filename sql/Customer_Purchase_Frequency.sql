SELECT
    c.Customer_ID,
    c.Country,
    COUNT(DISTINCT f.invoice_no) AS purchase_count,
    SUM(f.line_total)            AS lifetime_value,
    MIN(d.date)                  AS first_purchase,
    MAX(d.date)                  AS last_purchase
FROM fact_sales f
JOIN dim_customer c ON f.customer_key = c.customer_key
JOIN dim_date     d ON f.date_key      = d.date_key
GROUP BY c.Customer_ID, c.Country
ORDER BY lifetime_value DESC;
