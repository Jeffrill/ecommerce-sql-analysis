
/*
================================================================================
PROJECT: E-Commerce Business Health Analysis
AUTHOR: Omoake Jeffery
DATE: 11/26/2025
TOOL: SQL Server Management Studio
DATABASE: DESKTOP-UL28T5E\SQLEXPRESS

BUSINESS CONTEXT:
This analysis examines an e-commerce platform's user behavior, sales performance,
and product metrics to identify growth opportunities and operational improvements.

DATASET OVERVIEW:
- Users: Customer demographics and signup information
- Orders: Transaction records with status and amounts
- Order_Items: Line-item details for each order
- Products: Product catalog with categories, brands, and ratings

KEY QUESTIONS:
1. What is the quality and completeness of our data?
2. Who are our customers and where are they located?
3. What are our sales trends and performance metrics?
4. Which products and categories drive the most revenue?
5. What is our customer retention and repeat purchase rate?
6. How do returns impact our business?

ANALYSIS STRUCTURE:
Section 1: Data Quality Assessment
Section 2: Customer Demographics & Behavior
Section 3: Sales Performance Analysis
Section 4: Product & Category Insights
Section 5: Customer Retention & Cohort Analysis
Section 6: Key Findings & Recommendations
================================================================================
*/

--SECTION 1: DATA QUALITY ASSESSMENT
--1.1 Dataset Overview

/*
------------------------------------------------------------------
-- Objective: Understand the size and scpe of our dataset
-- Business Value: Establishes baseline for analysis
*/

--Total users in database
SELECT COUNT(DISTINCT user_id) AS total_users
FROM users

--Total orders and date range
SELECT COUNT(*) AS total_orders, MIN(order_date) AS earliest_date, MAX(order_date) AS latest_date
FROM orders

SELECT DATEDIFF(DAY,MIN(order_date),MAX(order_date)) AS days_of_data
FROM orders

--Total products
SELECT COUNT(*)AS total_products, COUNT(DISTINCT category) AS total_categories, COUNT(DISTINCT brand)AS total_brands
FROM products

/* Findings
1, We have 10,000 users over 683 days
- The dataset covers a total of 22 months
- There are 10 product categories available 
*/

/*
1.2 Missing Data Analysis

Objective: Identify the completness and data quality issues
Business Impact: Missing data canskew analysis and insights

-- Check for missing data in users table.
*/
SELECT 
COUNT(*) AS total_records,
SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) as missing_user_id,
SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) as missing_name,
SUM(CASE WHEN email IS NULL THEN 1 ELSE 0 END) as missing_email,
SUM(CASE WHEN city IS NULL THEN 1 ELSE 0 END) as missing_city,
SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) as missing_gender,
SUM(CASE WHEN signup_date IS NULL THEN 1 ELSE 0 END) as missing_signup_date,
-- Calculate percentage of missing data

CAST(SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
  as pct_missing_user_id,
  CAST(SUM(CASE WHEN email IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
  as pct_missing_email,
  CAST(SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
  as pct_missing_name,
  CAST(SUM(CASE WHEN city IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
  as pct_missing_city,
  CAST(SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
  as pct_missing_gender,
  CAST(SUM(CASE WHEN signup_date IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
  as pct_missing_signup_date

  FROM users

  /* Findings
  -- There are no missing data in the dataset.
      Largely due to the fact that it's a generated dataset from Faker, and numpy algorithm.


 1.3 Duplicate Detection
	  -- Objective: Find potentail duplicate records
	  -- Business Impact: Duplicates inflate metrics and skew analysis

	  -- Check for duplicate user records( same email)
	 */

	 SELECT email, COUNT(*) AS occurences
	 FROM users
	 WHERE email IS NOT NULL
	 GROUP BY email
	 HAVING COUNT(*) > 1
	 ORDER BY occurences DESC

-- Check for duplicate orders (same user, amount, date)
SELECT user_id, order_date,total_amount,COUNT(*) as duplicate_orders
FROM orders
GROUP BY user_id, order_date,total_amount
HAVING COUNT(*) > 1

/* FINDINGS
- No duplicate records were found in dataset.



1.4 Data Range Validation
-- Objective: find outliers and data quality issues
-- Business Impact: Outliers can indicate fraud, errors, or VIP customers

-- Check for suspicious order amounts
*/
SELECT DISTINCT
    MIN(total_amount) OVER() as min_order,
    MAX(total_amount) OVER() as max_order,
    AVG(total_amount) OVER() as avg_order,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_amount) OVER() as median_order,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_amount) OVER() as p95_order
FROM orders
WHERE order_status NOT IN ('cancelled', 'returned');

-- Then find outliers (orders more than 3 standard deviations from mean)
WITH stats AS ( SELECT 
                  AVG(total_amount) as mean_amount,
                  STDEV(total_amount) as std_amount
               FROM orders
               WHERE order_status NOT IN ('cancelled', 'returned'))
SELECT  o.order_id, o.user_id, o.total_amount, o.order_date,
    ROUND((o.total_amount - s.mean_amount) / s.std_amount, 2) as std_deviations_from_mean
FROM orders o
CROSS JOIN stats s
WHERE o.order_status NOT IN ('cancelled', 'returned')
    AND (o.total_amount > (s.mean_amount + 3 * s.std_amount) 
         OR o.total_amount < 0)
ORDER BY o.total_amount DESC;

-- Outlier Revenue percent
WITH order_stats AS ( SELECT  AVG(total_amount) as mean_amount,
                              STDEV(total_amount) as std_amount,
                              SUM(total_amount) as total_revenue
                     FROM orders
                     WHERE order_status IN ('completed', 'shipped'))
SELECT 
    SUM(CASE WHEN o.total_amount > (s.mean_amount + 3 * s.std_amount) 
        THEN o.total_amount ELSE 0 END) as outlier_revenue,  s.total_revenue,
    ROUND(SUM(CASE WHEN o.total_amount > (s.mean_amount + 3 * s.std_amount) 
        THEN o.total_amount ELSE 0 END) / s.total_revenue * 100, 2) as pct_of_revenue
FROM orders o
CROSS JOIN order_stats s
WHERE o.order_status IN ('completed', 'shipped')
GROUP BY s.total_revenue;

/* FINDINGS
-- The median_ order amount: 312.60 
   Average_order_amount: ~ 600, indicating that most customers spend 312.60 but a few customers, push the average up to 600 with larger orders.
   
-- The difference between the 95 percentile orders(2188.85) and the max_order(7490.93) indicates a great tendency for outliers.
- Total outliers: 292 orders (3+ standard deviations from mean)
-- Outlier range: 3.0 to 8.94 standard deviations from mean
-- Outlier revenue: 15.07% of total revenue



SECTION 2: Customer Demographics
   */

 SELECT  gender, COUNT(*) as customer_count, CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) as percentage
FROM users
WHERE gender IS NOT NULL
GROUP BY gender
ORDER BY customer_count DESC;

-- Top ten Cities by customers
SELECT TOP 10 city, COUNT(*) as customer_count, CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) as percentage
FROM users
WHERE city IS NOT NULL
GROUP BY city
ORDER BY customer_count DESC

;WITH city_revenue as (SELECT u.city,ROUND(SUM(o.total_amount),0) as total_revenue
                        FROM users u
						INNER JOIN orders o
						ON u.user_id = o.user_id
						GROUP BY u.city)
SELECT TOP 10 city, total_revenue, CAST(total_revenue * 100.0 / SUM(total_revenue) OVER() AS DECIMAL(5,2)) as pct
FROM city_revenue
ORDER BY total_revenue DESC

/* FINDINGS
-- The dataset is not skewed in terms of gender distribution. There are: 34.19% of other genders,
                                                                          33.34% females and,
																		  32.47% males.

-- The geographical distribution of the customers is way too thin, with only 13 out of 10000(0.13%) of customers in the most populated city of our customers.

RECOMMENDATIONS
- Awareness advertising to help expand customer base.

SECTION 2.2: CUSTOMER PURCHASE BEHAVIOUR
*/
-- Objective: Understand how customers shop
-- Business Impact: Identifies customer segments for targeted strategies 

--Orders per customer distribution

;WITH customer_orders AS( SELECT u.user_id, COUNT(o.order_id) as order_count,SUM(o.total_amount) as lifetime_value
						  FROM users u
						  LEFT JOIN orders o
						  ON u.user_id = o.user_id
						  AND order_status IN ( 'completed','shipped')
						  GROUP BY u.user_id)

SELECT CASE WHEN order_count = 0 THEN '0 orders'
			WHEN order_count = 1 THEN '1 order (one_time)'
		    WHEN order_count BETWEEN 2 AND 5 THEN '2-5 orders'
		    WHEN order_count BETWEEN 6 AND 10 THEN '6-10 orders'
	   	    ELSE '11+ orders (VIP)'
		    END AS customer_segment,
			COUNT(*) AS num_customers, ROUND(AVG(lifetime_value),2) as avg_lifetime_value,
			ROUND(SUM(lifetime_value),2) AS total_revenue
FROM customer_orders
GROUP BY 
	       CASE WHEN order_count = 0 THEN '0 orders'
			    WHEN order_count = 1 THEN '1 order (one_time)'
		        WHEN order_count BETWEEN 2 AND 5 THEN '2-5 orders'
				WHEN order_count BETWEEN 6 AND 10 THEN '6-10 orders'
			    ELSE '11+ orders (VIP)'
			    END 

ORDER BY total_revenue DESC
		       

-- CUSTOMER SEGMENT FINDINGS:
-- 44% of users never purchase (4,423 dead signups)
-- 36% are one-time buyers (3,616 customers - MAJOR retention problem)
-- Only 20% become repeat customers (major businesss drivers
-- Only 2 VIP customers (6-10 orders) 



-- RECOMMENDATIONS:
-- 1. Email campaign for "never purchased" segment with 15% first-order discount
-- 2. Post-purchase sequence for one-timers (thank you → product tips → offer at day 30)
-- 3. Investigate: Why aren't customers coming back? (pricing, selection, experience?)
				  

-- SECTION 2.3: Time To First Purchase
-- Objective: Measures time for signups to convert to customers
-- Business Impact: Measures onboarding effectiveness

SELECT 
    CASE WHEN days_to_first_order = 0 THEN 'Same day'
         WHEN days_to_first_order BETWEEN 1 AND 7 THEN '1-7 days'
         WHEN days_to_first_order BETWEEN 8 AND 30 THEN '8-30 days'
         WHEN days_to_first_order BETWEEN 31 AND 90 THEN '31-90 days'
         WHEN days_to_first_order > 90 THEN '90+ days'
         ELSE 'No purchase yet'
    END as conversion_timeframe,
    COUNT(*) as num_users, CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) as percentage
FROM ( SELECT  u.user_id, u.signup_date, MIN(o.order_date) as first_order_date,
        DATEDIFF(day, u.signup_date, MIN(o.order_date)) as days_to_first_order
       FROM users u
       LEFT JOIN orders o ON u.user_id = o.user_id
       GROUP BY u.user_id, u.signup_date) as user_conversion
GROUP BY
    CASE WHEN days_to_first_order = 0 THEN 'Same day'
         WHEN days_to_first_order BETWEEN 1 AND 7 THEN '1-7 days'
         WHEN days_to_first_order BETWEEN 8 AND 30 THEN '8-30 days'
         WHEN days_to_first_order BETWEEN 31 AND 90 THEN '31-90 days'
         WHEN days_to_first_order > 90 THEN '90+ days'
         ELSE 'No purchase yet'
    END
ORDER BY percentage DESC
   
/* INSIGHTS 
-- The conversion is poor. Only .19% of signup users make orders on the same day,
    only 88(0.88%) users order in the first 7 days after signup,277(2.77%) users order between 8-30 days,657(6.57%) users orders betwwen 31-90 days, 
	and 1970 users(19.70%) order after 90 days. Leaving a total of 6989(69.89%) of users as dead signups. 
-- This indicates that there is an issue with the onboarding process.
RECOMMENDATIONS: 
--Review the targeting strategy and the target audience.
*/



/* SECTION 3: SALES PERFORMANCE ANALYSIS
-- Objective: High-level business performance snapshot
-- Business Impact: KPI's for dashboard
*/

SELECT COUNT(DISTINCT order_id) as total_orders,
       COUNT(DISTINCT user_id) as unique_customers, 
	   ROUND(SUM(total_amount),0) as total_revenue,
	   ROUND(AVG(total_amount),2) as avg_order_value,
	   ROUND(SUM(total_amount) / COUNT(DISTINCT user_id),0) revenue_per_customer
FROM orders
WHERE order_status IN ('completed','shipped')

/* INSIGHTS
-- Total number of completed & shipped orders: 8134
-- Number of customers who have made purchases: 5577
-- Total revenue generated: $4,843,580


-- SECTION 3.2: REVENUE TRENDS OVER TIME
-- Objective: Identify growth patterns and seasonality
-- Business Impact: Informs inventory planning and marketing timing
 
 -- Monthly revenue trend
 */
 
 SELECT 
 YEAR(order_date) as Year, MONTH(order_date) as Month, 
 DATENAME(month,order_date) as month_name,COUNT(order_id) as order_count, 
 ROUND(SUM(total_amount),0) as monthly_revenue, ROUND(AVG(total_amount),2) as avg_order_value
FROM orders
WHERE order_status IN ('completed', 'shipped')
GROUP BY Year(order_date), MOnth(order_date), DATENAME(month,order_date)
ORDER BY Year,Month;


;WITH monthly_revenue AS ( SELECT YEAR(order_date) as year, MONTH(order_date) as month,SUM(total_amount) as revenue
                           FROM orders
                           WHERE order_status IN ('completed', 'shipped')
                           GROUP BY YEAR(order_date), MONTH(order_date))
SELECT year,month,revenue as current_revenue,
       LAG(revenue) OVER (PARTITION BY month ORDER BY year) as previous_year_revenue,
   CASE  WHEN LAG(revenue) OVER (PARTITION BY month ORDER BY year) IS NOT NULL 
   THEN  ROUND((revenue - LAG(revenue) OVER (PARTITION BY month ORDER BY year))  / LAG(revenue) OVER (PARTITION BY month ORDER BY year) * 100, 2)
   ELSE NULL 
   END as yoy_growth_pct
FROM monthly_revenue
ORDER BY year, month;

/* INSIGHTS TO FIND:
--There seems to be no clear pattern in increasing sales; March,May,June,July,and December had the best sales in 2024,
     but in 2025(April,June, October) generated the most revenue
-- There seems to be an fluctuating(rising and falling) growth rate trend in 2025,

*/

/* SECTION 3.3: ORDER STATUS BREAKDOWN
-- Objetive: Understand order fulfillment health
-- Business Impact: Returns and cancellations cost money*/

SELECT order_status, COUNT(*) as order_count, 
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) as pct_of_total,ROUND(SUM(total_amount),0) as total_value
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;

--INSIGHTS 
-- Orders that have been completed and shipped make for 40.68% of orders with a revenue of $4,843,580

-- Return-rate analysis
SELECT order_status, COUNT(*) as num_orders, ROUND(SUM(total_amount),0) as total_value
FROM orders
WHERE order_status = 'returned'
GROUP BY order_status

/* INSIGHTS
-- Our returns & canellation rate amount for a total of 39.93% of all our orders costing the business $4,725,618. 

--RECOMMENDATIONS
-- Inspect products before shipping.
-- Check customer reviews.


--SECTION 3.4: Geographic Revenue Analysis
-- Objective: Which cities drive the most business
-- Business Impact: Prioritize marketing spend by geography
*/
-- High revenue cities
SELECT TOP 10 u.city,COUNT(DISTINCT o.user_id) as uniques_customers,
               COUNT(o.order_id) as total_orders, ROUND(SUM(o.total_amount),0) as total_revenue,
			   ROUND(AVG(o.total_amount),2)as avg_order_value,ROUND(SUM(o.total_amount)/ COUNT(DISTINCT o.user_id),2) as revenue_per_customer
FROM users u
LEFT JOIN orders o
ON u.user_id = o.user_id
GROUP BY u.city
ORDER BY total_revenue DESC,uniques_customers DESC


--Low revenue cities
SELECT TOP 10 u.city,COUNT(DISTINCT o.user_id) as uniques_customers,
               COUNT(o.order_id) as total_orders, ROUND(SUM(o.total_amount),0) as total_revenue,
			   ROUND(AVG(o.total_amount),2)as avg_order_value,ROUND(SUM(o.total_amount)/ COUNT(DISTINCT o.user_id),2) as revenue_per_customer
FROM users u
LEFT JOIN orders o
ON u.user_id = o.user_id
WHERE total_amount IS NOT NULL
GROUP BY u.city
ORDER BY total_revenue ASC 

/* INSIGHTS
-- Not all top revenue cities are also top customer based cities (Lake Alyssamouth contains just one premium customer a total_ revenue of $13,289)
-- Lake Alyssamouth(AOV = $3,322.22), North Williamville(AOV = 1,614.97) are the two top average order value cities(AOV)
-- For the low-revenue cities, expansion is required, the total revenue is so low that it reveals the quality of products available in those cities.


--SECTION 4: PRODUCT & CATEGORY INSIGHTS
--4.1: Category Performance
-- Objective: Which products categories drive business
-- Business Impact: Inventory and merchandising decisions
*/
SELECT p.category, COUNT(DISTINCT oi.order_id) as total_orders, SUM(oi.quantity) as units_sold, 
       ROUND(SUM(oi.item_total) ,0) as total_revenue, ROUND(AVG(oi.item_total),2) as avg_item_value,
	   ROUND(AVG(p.rating),2) as avg_rating, ROUND(SUM(oi.item_total) / COUNT(DISTINCT oi.order_id),2) as avg_order_value
FROM order_items oi
INNER JOIN products p
ON oi.product_id = p.product_id
INNER JOIN orders o
ON oi.order_id = o.order_id
WHERE o.order_status In ('completed', 'shipped')
GROUP BY p.category
ORDER BY total_revenue DESC

/* INSIGHTS
-- On an average high-revenue categories do not have the highest ratings(e..g Electronics(highest revenue category - rating(3.69),
   whereas highest rating is 3.73)
-- There are three low-revenue markets to be targeted - Cothing(3.73 rating), Toys( 3.7) and Books(3.73)
-- Customer feedback should be reviewed for Automotive to see whats causing the low avg_ratings.
*/

--SECTION 4.2: Product Rating Vs. Sales Correlation
-- Objective: Do higher-rated products sell more?
-- Business Value: Understand importance of reviews

-- Highest revenue categories
SELECT 
    CASE WHEN p.rating < 3.0 THEN 'Low (<3.0)'
	     WHEN p.rating BETWEEN 3.0 AND 3.9 THEN 'Medium (3.0-3.9)'
		 WHEN p.rating BETWEEN 4.0 AND 4.4 THEN 'Good (4.0 - 4.4)'
		 WHEN p.rating >= 4.5 THEN 'Excellent (4.5+)'
    END as rating_category,
	COUNT(DISTINCT oi.product_id) as num_products,
	SUM(oi.quantity) as total_units_sold, ROUND(AVG(oi.quantity),2) as avg_units_per_product,
	ROUND(SUM(oi.item_total),0) as total_revenue
FROM products p
INNER JOIN order_items oi 
ON p.product_id = oi.product_id
INNER JOIN orders o 
ON o.order_id = oi.order_id
WHERE o.order_status IN ('completed', 'shipped')
GROUP BY 
        CASE WHEN p.rating < 3.0 THEN 'Low (<3.0)'
	     WHEN p.rating BETWEEN 3.0 AND 3.9 THEN 'Medium (3.0-3.9)'
		 WHEN p.rating BETWEEN 4.0 AND 4.4 THEN 'Good (4.0 - 4.4)'
		 WHEN p.rating >= 4.5 THEN 'Excellent (4.5+)'
		 END
ORDER BY total_revenue DESC

-- Revenue per brand
SELECT p.brand,ROUND(SUM(oi.item_total) ,0) as total_revenue,
       ROUND(AVG(oi.item_total),2) as avg_item_value,ROUND(AVG(p.rating),2) as avg_rating
FROM products p
INNER JOIN order_items oi
ON p.product_id = oi.product_id
GROUP BY p.brand
ORDER BY total_revenue DESC

-- Best performing products
SELECT TOP 10 p.product_name,ROUND(SUM(oi.item_total) ,0) as total_revenue,
       ROUND(AVG(oi.item_total),2) as avg_item_value,ROUND(AVG(p.rating),2) as avg_rating, p.category
FROM products p
INNER JOIN order_items oi
ON p.product_id = oi.product_id
GROUP BY p.product_name,p.category
ORDER BY total_revenue DESC

/* INSIGHTS
-- There is weak correlation between sales and rating, this means ratings do not drive sales.*/
-- Customers purchase more products in Electronics than in any other category.
-- 90% of the top ten best performing products are Electronic products

/* SECTION 5; CUSTOMER RETENTION & COHORT ANALYSIS
5.1: Repeat Purchase Rate

-- Objective: How many customers come back?
-- Business Value: Retention is cheaper than acquisition
*/

;WITH customer_purchase_count AS ( SELECT user_id,COUNT(order_id)as purchase_count
                                    FROM orders
									WHERE Order_status IN ('completed', 'shipped')
									GROUP BY user_id)
SELECT 
   COUNT(CASE WHEN purchase_count = 1 THEN 1 END) as one_time_customers,
   COUNT(CASE WHEN purchase_count > 1 THEN 1 END)  as repeat_customers, 
   ROUND(CAST(COUNT(CASE WHEN purchase_count > 1 THEN 1 END) AS FLOAT)/ COUNT(*) * 100.0,2) as repeat_purchase_rate_pct
FROM customer_purchase_count;


/* INSIGHTS
-- The repeat_purchase rate is 35.61% which is a good rate, we have 3616 one-time customers and 1961 repeat customers


-- SECTION 5.2: Cohort Analysis by Signup Month
-- Objective: Do certain signup months retain better?
-- Business Value: Identifies successful acquisition campaigns */

WITH user_cohorts AS ( SELECT u.user_id, DATEFROMPARTS(YEAR(u.signup_date),MONTH(u.signup_date),1)as cohort_month, 
                       MIN(o.order_date) as first_order_date, COUNT(o.order_id)as total_orders,SUM(o.total_amount)as lifetime_value
					   FROM users u
					   LEFT JOIN orders o 
					   ON u.user_id = o.user_id
					   GROUP BY u.user_id,  DATEFROMPARTS(YEAR(u.signup_date),MONTH(u.signup_date),1))
SELECT cohort_month, COUNT(user_id) as cohort_size, COUNT(first_order_date) as customers_who_purchased,
        ROUND(CAST(COUNT(first_order_date) AS FLOAT) / COUNT(user_id) * 100,2) as conversion_rate_pct,
		ROUND(AVG(total_orders),2) as avg_orders_per_user,
		ROUND(AVG(lifetime_value),2) as avg_lifetime_value
FROM user_cohorts
GROUP BY cohort_month
ORDER BY cohort_month;

/* INSIGHTS 
-- Feburary(2024) had the best converting cohorts(90.79% conversion), 
   November(2024) with 88.32% conversion, 
   August(2025) - 87.99% conversion,
   October(2024) - 87.47% conversion,
   Maay(2025) - 87.35% conversion.


-- SECTION 5.3: Days Between Purchases
-- Objective: How often do repeart customers return?
-- Business Value: Timing for retention campaigns*/

;WITH purchase_gaps AS( SELECT user_id, order_date, LAG(order_date) OVER (PARTITION BY user_id ORDER BY order_date) as previous_order_date,
                        DATEDIFF(day, LAG(order_date) OVER (PARTITION BY user_id ORDER BY order_date),order_date) as days_since_last_order
						FROM orders
						WHERE order_status IN ('completed', 'shipped'))

SELECT 
     CASE WHEN days_since_last_order IS NULL THEN 'First_purchase'
	      WHEN days_since_last_order <= 30 THEN '0-30 days'
		  WHEN days_since_last_order BETWEEN 31 AND 60 THEN '31-60 days'
		  WHEN days_since_last_order BETWEEN 61 AND 90 THEN '61-90 days'
		  WHEN days_since_last_order > 90 THEN '90+ days'
		  END AS purchase_frequency,
	COUNT(*) as order_count
FROM purchase_gaps
GROUP BY 
        CASE WHEN days_since_last_order IS NULL THEN 'First_purchase'
	      WHEN days_since_last_order <= 30 THEN '0-30 days'
		  WHEN days_since_last_order BETWEEN 31 AND 60 THEN '31-60 days'
		  WHEN days_since_last_order BETWEEN 61 AND 90 THEN '61-90 days'
		  WHEN days_since_last_order > 90 THEN '90+ days'
		  END

ORDER BY order_count DESC

-- INSIGHTS
-- The most common purchase gap after first purchase is after 90 days(1809 orders), 
-- the 30,60 and 90 day gaps have roughly the same order amount (266, 237,245 orders respectively).


/* SECTION 6: 
================================================================================
EXECUTIVE SUMMARY: E-COMMERCE BUSINESS ANALYSIS
================================================================================

PROJECT OVERVIEW:
This portfolio project analyzes e-commerce data including 10,000 customers, 
20,000 orders, and 2000 products over 22 months. The goal was to uncover 
customer behavior patterns, identify sales trends, and evaluate retention 
metrics using SQL. 

KEY FINDINGS

1. Customer Conversion Challenge
   • 44% of signups (4,423 users) never made a purchase
   • Signup-to-purchase conversion: 56% (below typical 60-80% benchmark)
   • Finding: Significant drop-off in the user journey from signup to first order
   • The 19.70% of users make a purchase after a 90 days(best conversion timeframe) of signing up

2. Customer Retention Performance
   • 36% of buyers (3,616 customers) made only one purchase ($2.19M revenue)
   • Repeat purchase rate: 35% among buyers (within acceptable 25-40% range)
   • Repeat customers spend 2.2x more on average ($1,352 vs $605 first order)
   • Insight: Repeat customers are significantly more valuable but underrepresent

3. [YOUR GEOGRAPHIC/CITY FINDING]
   • Top 10 cities in revenue generation only represent 1.25% of revenue
   • Average Order Value varies by location and not by customer concentration. Lake Alyssamouth has the highest AOV($3,322.22) but has just one customer
   • Insight: Revenue is spread very evenly with only North Michael having a slightly greater revenue of $22,082

4. PRODUCT & CATEGORY FINDING
  • The highest revenue category was Electronics with $1,990,350 total revenue generated 
     and average rating of 3.69, followed by Automotives with $1,035,700 total revenue generated.
  • The top ten best performing products were Electronis with one 
     Automotive(Willow Hospital) at no. 6
  •  The highest revenue brand is Willow with $1,333,670 in total revenue followed by 
     Orion with $1,156,620 
  • Insight: Electronic products recive more appreciation from customers than 
     any other product type.

5.COHORT/RETENTION FINDING 
   • Cohort conversion rates for each month was great with range of 83.01% to 90.79%
   • Insight: Customers tend to make an order after a 90 day period since previous order



POTENTIAL BUSINESS APPLICATIONS:
If this were real business data, these findings would suggest:
- Optimizing onboarding flow to improve signup-to-purchase conversion
- Implementing retention campaigns targeting one-time buyers
- Targeted expansion needed customer base is spread too thin among many cities.
- Awareness advertising is urgently needed.

TECHNICAL SKILLS DEMONSTRATED:
✓ Complex SQL queries: JOINs, CTEs, subqueries, window functions
✓ Data quality assessment: identifying nulls, duplicates, outliers
✓ Customer segmentation and cohort analysis
✓ Business metrics: conversion rates, retention, lifetime value
✓ Statistical analysis: percentiles, distributions, aggregations

DATA NOTES:
- Dataset: 
--This dataset is a synthetic yet realistic E-commerce retail dataset gotten from Kaggle;generated programmatically using Python (Faker + NumPy + Pandas). 
-- It is designed to closely mimic real-world online shopping behavior, user patterns, product interactions, seasonal trends, and marketplace events.

- Date Range: 
--The dataset covered 22 months of business records,involving 10,000 customers,20,000 orders,2000 products and 10 product categories 

- Data Quality: 
-- There was no missing data in the dataset, and also no duplicates were found.
-- 292 statistical outliers (15% of revenue) retained as legitimate high-value transactions

- Limitations: 
--The data contained no missing data
-- The customers where spread too thinly amoong the cities,so it was largely impossible to tell if greater advertisement should be launched in cities with large customer base.

TOOLS & TECHNOLOGIES:
SQL Server Management Studio, PowerBI

*/



