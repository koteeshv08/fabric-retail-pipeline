SELECT
    c.Country,
    SUM(f.line_total)            AS total_revenue,
    COUNT(DISTINCT c.Customer_ID) AS unique_customers,
    COUNT(DISTINCT f.invoice_no) AS total_orders
FROM fact_sales f
JOIN dim_customer c ON f.customer_key = c.customer_key
GROUP BY c.Country
ORDER BY total_revenue DESC;
