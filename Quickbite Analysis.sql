
SELECT * FROM fact_orders;
SELECT * FROM fact_order_items;
SELECT * FROM fact_ratings;
SELECT * FROM fact_delivery_performance;
SELECT * FROM dim_customer;
SELECT * FROM dim_delivery_partner_;
SELECT * FROM dim_menu_item;
SELECT * FROM dim_restaurant;

-- Primary Analysis (Based on Available data):

-- 1. Monthly Orders: Compare total orders across pre-crisis (Jan–May 2025) vs crisis (Jun–Sep 2025). How severe is the decline?

SELECT COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN order_id END) AS pre_crisis_total_orders,
COUNT(CASE WHEN order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN order_id END) AS crisis_total_orders,
CONCAT(FORMAT(100.0 * (COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN order_id END) -
COUNT(CASE WHEN order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN order_id END)) /
COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN order_id END), '00.00'), ' %') AS decline_percent
FROM fact_orders 
WHERE is_cancelled = 'N';


-- 2. Which top 5 city groups experienced the highest percentage decline in orders during the crisis period compared to the pre-crisis period?

SELECT TOP 5 c.city, 
COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END) AS pre_crisis_total_orders,
COUNT(CASE WHEN order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN o.order_id END) AS crisis_total_orders,
CONCAT(FORMAT(100.0 * (COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END) -
COUNT(CASE WHEN order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN o.order_id END)) /
COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END), '00.00'), ' %') AS decline_percent
FROM fact_orders o
JOIN dim_customer c ON o.customer_id = c.customer_id
WHERE is_cancelled = 'N'
GROUP BY c.city
ORDER BY decline_percent DESC;


-- 3. Among restaurants with at least 50 pre-crisis orders, which top 10 high-volume restaurants experienced the largest percentage decline 
--    in order counts during the crisis period?

SELECT TOP 10 r.restaurant_name, 
COUNT(CASE WHEN o.order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END) AS pre_crisis_total_orders,
COUNT(CASE WHEN o.order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN o.order_id END) AS crisis_total_orders,
CONCAT(FORMAT(100.0 * (COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN order_id END) -
COUNT(CASE WHEN o.order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN o.order_id END)) /
COUNT(CASE WHEN o.order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END), '00.00'), ' %') AS decline_percent
FROM fact_orders o
JOIN dim_restaurant r ON o.restaurant_id = r.restaurant_id
WHERE o.is_cancelled = 'N' AND r.is_active = 'Y'
GROUP BY r.restaurant_name
HAVING COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END) >= 50
ORDER BY pre_crisis_total_orders DESC, decline_percent DESC;


-- 4. Which types of restaurants (cloud kitchens vs dine-in) haved churned?

SELECT r.partner_type, COUNT(o.order_id) AS total_orders_before_churning, SUM(o.total_amount) AS total_revenue_before_churning
FROM fact_orders o
JOIN dim_restaurant r ON o.restaurant_id = r.restaurant_id AND r.is_active = 'N'
GROUP BY r.partner_type;


-- 5. Cancellation Analysis: What is the cancellation rate trend pre-crisis vs crisis, and which cities are most affected?

SELECT c.city,
COUNT(CASE WHEN o.order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END) AS pre_crisis_total_cancelled_orders,
COUNT(CASE WHEN o.order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN o.order_id END) AS crisis_total_cancelled_orders,
CONCAT(FORMAT(100.0 * (COUNT(CASE WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN order_id END) -
COUNT(CASE WHEN o.order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN o.order_id END)) /
COUNT(CASE WHEN o.order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN o.order_id END), '00.00'), ' %') AS decline_percent
FROM fact_orders o 
JOIN dim_customer c ON o.customer_id = c.customer_id
WHERE o.is_cancelled = 'Y'
GROUP BY c.city
ORDER BY decline_percent DESC;

-- 6. Delivery SLA: Measure average delivery time across phases. Did SLA compliance worsen significantly in the crisis period?

WITH cte AS (
SELECT o.order_id, o.order_timestamp, 
CASE 
	WHEN o.order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN 'Pre-crisis'
	WHEN o.order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN 'Crisis' 
END AS phases,
dp.actual_delivery_time_mins,  
CASE WHEN dp.actual_delivery_time_mins <= dp.expected_delivery_time_mins THEN 'On Time' ELSE 'Late' END AS timely_delivery
FROM fact_orders o
JOIN fact_delivery_performance dp ON o.order_id = dp.order_id
WHERE o.is_cancelled = 'N'
)
SELECT phases, AVG(actual_delivery_time_mins) AS avg_delivery_time_mins, 
CONCAT(FORMAT(COUNT(CASE WHEN timely_delivery = 'On Time' THEN order_id END) * 100.0 / COUNT(*), '00.00'), ' %') AS 'SLA compliance rate (on time) deliveries',
CONCAT(FORMAT(COUNT(CASE WHEN timely_delivery = 'Late' THEN order_id END) * 100.0 / COUNT(*), '00.00'), ' %') AS 'SLA compliance rate (late) deliveries'
FROM cte
GROUP BY phases;


-- 7. Ratings Fluctuation: Track average customer rating month-by-month. Which months saw the sharpest drop?

WITH cte AS (
SELECT MONTH(review_timestamp) AS review_month, ROUND(AVG(rating), 2) AS avg_rating
FROM fact_ratings
GROUP BY MONTH(review_timestamp)
)
SELECT review_month, avg_rating
FROM (
	SELECT *, NTILE(2) OVER(ORDER BY review_month, avg_rating DESC) AS month_rank
	FROM cte
) p
WHERE month_rank = 2;


-- 8. Sentiment Insights: During the crisis period, identify the most frequently occurring negative keywords in customer review texts. 
-- (Hint: Use a Word Cloud visual in Power BI to visualize the findings.)

SELECT review_text, COUNT(review_text) AS frequency
FROM (
	SELECT review_text, sentiment_score
	FROM fact_ratings  
	WHERE review_timestamp BETWEEN '2025-05-31' AND '2025-10-01'
) R
WHERE sentiment_score <= 0.7
GROUP BY review_text
ORDER BY 2 DESC;


-- 9. Revenue Impact: Estimate revenue loss from pre-crisis vs crisis (based on subtotal, discount, and delivery fee).

WITH cte AS (
SELECT  
CASE 
	WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN 'Pre-crisis'
	WHEN order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN 'Crisis' 
END AS phases,
SUM(total_amount) AS revenue
FROM fact_orders
WHERE is_cancelled = 'N'
GROUP BY 
CASE 
	WHEN order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN 'Pre-crisis'
	WHEN order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN 'Crisis' 
END
)
SELECT *, 
CONCAT(FORMAT(100.0 * (revenue - LAG(revenue) OVER(ORDER BY revenue DESC)) / LAG(revenue) OVER(ORDER BY revenue DESC), '00.00'), ' %') AS revenue_loss_percent
FROM cte;


-- 10. Loyalty Impact: Among customers who placed five or more orders before the crisis, determine how many stopped ordering during the crisis, 
--    and out of those, how many had an average rating above 4.5?

WITH cte1 AS (
SELECT customer_id, COUNT(order_id) AS pre_crisis_total_orders
FROM fact_orders 
WHERE order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' AND is_cancelled = 'N'
GROUP BY customer_id
HAVING COUNT(order_id) >= 5
),
cte2 AS (
SELECT c.customer_id, c.pre_crisis_total_orders, 
CASE WHEN o.order_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN 1 ELSE 0 END AS crisis_order_flag
FROM cte1 c
JOIN fact_orders o ON c.customer_id = o.customer_id
),
cte3 AS (
SELECT c2.customer_id, c2.crisis_order_flag, AVG(r.rating) AS avg_rating_crisis
FROM cte2 c2
JOIN fact_ratings r ON c2.customer_id = r.customer_id
GROUP BY c2.customer_id, c2.pre_crisis_total_orders, c2.crisis_order_flag
HAVING AVG(r.rating) > 4.5
)
SELECT (SELECT COUNT(customer_id) FROM cte1) AS 'customers placed >=5 orders before crisis',
COUNT(avg_rating_crisis) AS 'customers gave >4.5 rating',
COUNT(CASE WHEN crisis_order_flag = 0 THEN customer_id END) AS 'customers stopped ordering during crisis count',
COUNT(CASE WHEN crisis_order_flag = 1 THEN customer_id END) AS 'customers ordering in crisis count'
FROM cte3;


-- 11. Customer Lifetime Decline: Which high-value customers (top 5% by total spend before the crisis) showed the largest drop in order 
--     frequency and ratings during the crisis? What common patterns (e.g., location, cuisine preference, delivery delays) do they share?

WITH cte AS (
SELECT customer_id, COUNT(order_id) AS pre_crisis_total_orders,
SUM(total_amount) AS pre_crisis_total_spend, PERCENT_RANK() OVER(ORDER BY SUM(total_amount) DESC) AS rank_percent
FROM fact_orders 
WHERE order_timestamp BETWEEN '2024-12-31' AND '2025-06-01' AND is_cancelled = 'N'
GROUP BY customer_id
),
top_spenders AS (
SELECT * FROM cte WHERE rank_percent <= 0.05
),
crisis_details AS (
SELECT ts.customer_id, ts.pre_crisis_total_spend, ts.pre_crisis_total_orders,
COUNT(CASE WHEN r.review_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN r.order_id END) AS crisis_total_orders,
AVG(CASE WHEN r.review_timestamp BETWEEN '2024-12-31' AND '2025-06-01' THEN r.rating END) AS pre_crisis_avg_rating, 
AVG(CASE WHEN r.review_timestamp BETWEEN '2025-05-31' AND '2025-10-01' THEN r.rating ELSE 0 END) AS crisis_avg_rating 
FROM top_spenders ts
JOIN fact_ratings r ON ts.customer_id = r.customer_id
GROUP BY ts.customer_id, ts.pre_crisis_total_spend, ts.pre_crisis_total_orders
)
SELECT cd.customer_id, cd.pre_crisis_total_spend, cd.pre_crisis_total_orders, cd.crisis_total_orders, cd.pre_crisis_avg_rating, 
cd.crisis_avg_rating, c.city, res.cuisine_type,
CASE WHEN dp.actual_delivery_time_mins <= dp.expected_delivery_time_mins THEN 'On Time' ELSE 'Late' END AS timely_delivery_of_orders
FROM crisis_details cd
JOIN dim_customer c ON cd.customer_id = c.customer_id
JOIN fact_orders o ON cd.customer_id = o.customer_id
JOIN dim_restaurant res ON o.restaurant_id = res.restaurant_id
JOIN fact_delivery_performance dp ON o.order_id = dp.order_id
ORDER BY cd.pre_crisis_total_spend DESC;

