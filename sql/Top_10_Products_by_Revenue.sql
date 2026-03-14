SELECT TOP 10
    p.StockCode,
    p.Description,
    SUM(f.quantity)    AS units_sold,
    SUM(f.line_total)  AS total_revenue
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.StockCode, p.Description
ORDER BY total_revenue DESC;
