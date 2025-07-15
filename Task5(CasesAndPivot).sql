USE StoreDB;

--Classify products into price categories

SELECT product_id, product_name,
       CASE
           WHEN list_price < 300 THEN 'Economy'
           WHEN list_price BETWEEN 300 AND 999 THEN 'Standard'
           WHEN list_price BETWEEN 1000 AND 2499 THEN 'Premium'
           ELSE 'Luxury'
       END AS PRICE_CATEGORY
FROM production.products;

--Order processing info with user-friendly status & priority

SELECT order_id, customer_id, order_date,
       CASE order_status
           WHEN 1 THEN 'Order Received'
           WHEN 2 THEN 'In Preparation'
           WHEN 3 THEN 'Order Cancelled'
           WHEN 4 THEN 'Order Delivered'
       END AS STATUS_CASE,
       CASE
           WHEN order_status = 1 AND DATEDIFF(DAY, order_date, GETDATE()) > 5 THEN 'URGENT'
           WHEN order_status = 2 AND DATEDIFF(DAY, order_date, GETDATE()) > 3 THEN 'HIGH'
           ELSE 'NORMAL'
       END AS PRIORITY
FROM sales.orders;

--Categorize staff based on number of orders

SELECT s.staff_id, s.first_name + ' ' + s.last_name AS staff_name,
       COUNT(o.order_id) AS ORDERS,
       CASE
           WHEN COUNT(o.order_id) = 0 THEN 'New Staff'
           WHEN COUNT(o.order_id) BETWEEN 1 AND 10 THEN 'Junior Staff'
           WHEN COUNT(o.order_id) BETWEEN 11 AND 25 THEN 'Senior Staff'
           ELSE 'Expert Staff'
       END AS staff_category
FROM sales.staffs s
LEFT JOIN sales.orders o ON s.staff_id = o.staff_id
GROUP BY s.staff_id, s.first_name, s.last_name;

--Handle missing customer contact info

SELECT customer_id, first_name, last_name,
       ISNULL(phone, 'Phone Not Available') AS PHONE,
       email,
       COALESCE(phone, email, 'No Contact Method') AS PERFECT_CONTACT
FROM sales.customers;

--Safe price per unit in stock

SELECT product_name, store_id, quantity,
       ISNULL(NULLIF(quantity, 0), 0) AS ITEMS_FOUNDED,
       ISNULL(list_price / NULLIF(quantity, 0), 0) AS PRICE_PER_UNIT,
       CASE
           WHEN quantity = 0 THEN 'Out of Stock'
           WHEN quantity IS NULL THEN 'Unknown'
           ELSE 'In Stock'
       END AS stock_status
FROM production.stocks s
JOIN production.products p ON s.product_id = p.product_id
WHERE store_id = 1;

--Format complete addresses

SELECT customer_id, 
       COALESCE(street, '') + ', ' + COALESCE(city, '') + ', ' + COALESCE(state, '') + ', ' + COALESCE(zip_code, 'ZIP Not Available') AS formatted_address
FROM sales.customers;

--CTE: Customers who spent more than $1500

WITH customer_spending AS (
    SELECT customer_id, SUM(list_price * quantity) AS TOTAL
    FROM sales.orders o
    JOIN sales.order_items i ON o.order_id = i.order_id
    GROUP BY customer_id
)
SELECT c.customer_id, first_name, last_name, TOTAL
FROM customer_spending cs
JOIN sales.customers c ON cs.customer_id = c.customer_id
WHERE TOTAL > 1500
ORDER BY TOTAL DESC;

--Multi-CTE for category analysis (USED AI IN THIS)
WITH revenue_cte AS (
    SELECT c.category_id, c.category_name, SUM(i.list_price * i.quantity) AS total_revenue
    FROM production.products p
    JOIN production.categories c ON p.category_id = c.category_id
    JOIN sales.order_items i ON p.product_id = i.product_id
    GROUP BY c.category_id, c.category_name
),
average_cte AS (
    SELECT c.category_id, AVG(i.list_price * i.quantity) AS avg_order_value
    FROM production.products p
    JOIN production.categories c ON p.category_id = c.category_id
    JOIN sales.order_items i ON p.product_id = i.product_id
    GROUP BY c.category_id
)
SELECT r.category_name, r.total_revenue, a.avg_order_value,
       CASE 
           WHEN r.total_revenue > 50000 THEN 'Excellent'
           WHEN r.total_revenue > 20000 THEN 'Good'
           ELSE 'Needs Improvement'
       END AS performance
FROM revenue_cte r
JOIN average_cte a ON r.category_id = a.category_id;

--CTE: Monthly sales trends (AI)

WITH monthly_sales AS (
    SELECT MONTH(order_date) AS month, SUM(list_price * quantity) AS TOTAL
    FROM sales.orders o
    JOIN sales.order_items i ON o.order_id = i.order_id
    GROUP BY MONTH(order_date)
),
monthly_comparison AS (
    SELECT month, TOTAL,
           LAG(TOTAL) OVER (ORDER BY month) AS MONTH_SALES
    FROM monthly_sales
)
SELECT month, TOTAL, MONTH_SALES,
       ROUND((TOTAL - MONTH_SALES) * 100.0 / NULLIF(MONTH_SALES, 0), 2) AS GROTH
FROM monthly_comparison;

--Rank products in each category

WITH ranked_products AS (
    SELECT product_id, product_name, category_id, list_price,
           ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY list_price DESC) AS ROW_NUMBER,
           RANK() OVER (PARTITION BY category_id ORDER BY list_price DESC) AS RANK,
           DENSE_RANK() OVER (PARTITION BY category_id ORDER BY list_price DESC) AS DENSE_RANK
    FROM production.products
)
SELECT *
FROM ranked_products
WHERE ROW_NUMBER <= 3;

--Rank customers by spending and assign tiers

WITH spending_cte AS (
    SELECT customer_id, SUM(list_price * quantity) AS TOTAL
    FROM sales.orders o
    JOIN sales.order_items i ON o.order_id = i.order_id
    GROUP BY customer_id
)
SELECT customer_id, TOTAL,
       RANK() OVER (ORDER BY TOTAL DESC) AS RANK,
       NTILE(5) OVER (ORDER BY TOTAL DESC) AS SPENDING,
       CASE NTILE(5) OVER (ORDER BY TOTAL DESC)
           WHEN 1 THEN 'VIP'
           WHEN 2 THEN 'Gold'
           WHEN 3 THEN 'Silver'
           WHEN 4 THEN 'Bronze'
           ELSE 'Standard'
       END AS TIERS
FROM spending_cte;

--Store performance ranking (AI)

WITH store_data AS (
    SELECT store_id, 
           SUM(list_price * quantity) AS revenue,
           COUNT(O.order_id) AS order_count
    FROM sales.orders o
    JOIN sales.order_items i ON o.order_id = i.order_id
    GROUP BY store_id
)
SELECT store_id, revenue, order_count,
       RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
       RANK() OVER (ORDER BY order_count DESC) AS order_rank,
       PERCENT_RANK() OVER (ORDER BY revenue) AS revenue_percentile
FROM store_data;

--PIVOT product counts by category and brand

SELECT *
FROM (
    SELECT c.category_name, b.brand_name
    FROM production.products p
    JOIN production.categories c ON p.category_id = c.category_id
    JOIN production.brands b ON p.brand_id = b.brand_id
) AS SOURCE
PIVOT (
    COUNT(brand_name) FOR brand_name IN ([Electra], [Haro], [Trek], [Surly])
) AS PIVOT_TABLE;

--PIVOT monthly sales revenue by store
--Assume month is extracted from order_date

SELECT *
FROM (
    SELECT s.store_name, MONTH(o.order_date) AS MONTH, i.list_price * i.quantity AS REVENUE
    FROM sales.orders o
    JOIN sales.order_items i ON o.order_id = i.order_id
    JOIN sales.stores s ON o.store_id = s.store_id
) AS SOURCE
PIVOT (
    SUM(revenue) FOR month IN ([1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12])
) AS PIVOT_TABLE;

--PIVOT order statuses across stores

SELECT *
FROM (
    SELECT s.store_name, o.order_status
    FROM sales.orders o
    JOIN sales.stores s ON o.store_id = s.store_id
) AS SOURCE
PIVOT (
    COUNT(order_status) FOR order_status IN ([1], [2], [3], [4])
) AS PIVOT_TABLE;

-- 16. PIVOT comparing sales across years
WITH sales_years AS (
    SELECT b.brand_name, YEAR(o.order_date) AS sales_year, i.list_price * i.quantity AS revenue
    FROM sales.orders o
    JOIN sales.order_items i ON o.order_id = i.order_id
    JOIN production.products p ON i.product_id = p.product_id
    JOIN production.brands b ON p.brand_id = b.brand_id
)
SELECT *
FROM sales_years
PIVOT (
    SUM(revenue) FOR sales_year IN ([2016], [2017], [2018])
) AS PIVOT_TABLE;

--UNION for product availability

SELECT product_id, 'In Stock' AS availabal FROM production.stocks WHERE quantity > 0
UNION
SELECT product_id, 'Out of Stock' FROM production.stocks WHERE quantity <= 0 OR quantity IS NULL
UNION
SELECT product_id, 'Discontinued' FROM production.products
WHERE product_id NOT IN (SELECT product_id FROM production.stocks);

--INTERSECT loyal customers

SELECT customer_id FROM sales.orders WHERE YEAR(order_date) = 2017
INTERSECT
SELECT customer_id FROM sales.orders WHERE YEAR(order_date) = 2018;

--Multiple set operators for product distribution

SELECT product_id FROM production.stocks WHERE store_id = 1
INTERSECT
SELECT product_id FROM production.stocks WHERE store_id = 2
INTERSECT
SELECT product_id FROM production.stocks WHERE store_id = 3
UNION
SELECT product_id FROM production.stocks WHERE store_id = 1
EXCEPT
SELECT product_id FROM production.stocks WHERE store_id = 2;

--Complex set operations for customer retention

SELECT customer_id, 'Lost Customer' AS status FROM sales.orders WHERE YEAR(order_date) = 2016
EXCEPT
SELECT customer_id FROM sales.orders WHERE YEAR(order_date) = 2017
UNION ALL
SELECT customer_id, 'New Customer' FROM sales.orders WHERE YEAR(order_date) = 2017
EXCEPT
SELECT customer_id FROM sales.orders WHERE YEAR(order_date) = 2016
UNION ALL
SELECT customer_id, 'Retained Customer' FROM sales.orders WHERE YEAR(order_date) = 2016
INTERSECT
SELECT customer_id FROM sales.orders WHERE YEAR(order_date) = 2017;
