-- Chinook Data Warehouse Project
-- File: 02_analysis_queries.sql
-- Purpose: Business analysis queries based on the DWH model.

-- 1. Playlist size analysis: largest and smallest playlists compared with average playlist size
WITH playlist_track_counts AS (
    SELECT
        bpt.playlist_id,
        bpt.playlist_name,
        COUNT(bpt.track_id) AS tracks_count
    FROM dwh.dim_playlist  bpt
    GROUP BY bpt.playlist_id, bpt.playlist_name
),
playlist_rankings AS (
    SELECT
        playlist_id,
        playlist_name,
        tracks_count,
        RANK() OVER (ORDER BY tracks_count DESC) AS rank_max,
        RANK() OVER (ORDER BY tracks_count ASC) AS rank_min,
        ROUND(AVG(tracks_count) OVER (), 2) AS avg_tracks_count
    FROM playlist_track_counts
)
SELECT *
FROM playlist_rankings
WHERE rank_max = 1 OR rank_min = 1
ORDER BY tracks_count DESC;

-- 2. Track sales distribution: how many tracks fall into each sales bucket
WITH track_sales AS (
    SELECT
        dt.track_id,
        dt.track_name,
        COUNT(fil.track_id) AS sales_count
    FROM dwh.dim_track dt
    LEFT JOIN dwh.fact_invoice_line fil
        ON dt.track_id = fil.track_id
    GROUP BY dt.track_id, dt.track_name
),
track_sales_groups AS (
    SELECT
        track_id,
        track_name,
        sales_count,
        CASE
            WHEN sales_count = 0 THEN '0'
            WHEN sales_count BETWEEN 1 AND 5 THEN '1-5'
            WHEN sales_count BETWEEN 6 AND 10 THEN '6-10'
            ELSE '>10'
        END AS sales_group
    FROM track_sales
)
SELECT
    sales_group,
    COUNT(*) AS tracks_count
FROM track_sales_groups
GROUP BY sales_group
ORDER BY
    CASE sales_group
        WHEN '0' THEN 1
        WHEN '1-5' THEN 2
        WHEN '6-10' THEN 3
        ELSE 4
    END;

-- 3A. Country sales ranking: top 5 and bottom 5 countries by total revenue
DROP VIEW IF EXISTS dwh.v_country_sales_rankings;

CREATE VIEW dwh.v_country_sales_rankings AS
WITH country_sales AS (
    SELECT
        billing_country AS country,
        SUM(total_usd) AS total_sales_usd
    FROM dwh.fact_invoice
    GROUP BY billing_country
),
country_sales_ranking AS (
    SELECT
        country,
        total_sales_usd,
        RANK() OVER (ORDER BY total_sales_usd DESC) AS rank_max,
        RANK() OVER (ORDER BY total_sales_usd ASC) AS rank_min
    FROM country_sales
)
SELECT
    country,
    ROUND(total_sales_usd, 2) AS total_sales_usd,
    CASE
        WHEN rank_max <= 5 THEN 'Top 5'
        WHEN rank_min <= 5 THEN 'Bottom 5'
    END AS country_group
FROM country_sales_ranking
WHERE rank_max <= 5 OR rank_min <= 5;

SELECT *
FROM dwh.v_country_sales_rankings
ORDER BY country_group DESC, total_sales_usd DESC;

-- 3B. Genre mix analysis for top and bottom countries
WITH country_genre_sales AS (
    SELECT
        vcsr.country,
        vcsr.country_group,
        dt.genre_name,
        SUM(fil.total_line) AS genre_sales_usd,
        vcsr.total_sales_usd
    FROM dwh.v_country_sales_rankings vcsr
    JOIN dwh.fact_invoice fi
        ON vcsr.country = fi.billing_country
    JOIN dwh.fact_invoice_line fil
        ON fi.invoice_id = fil.invoice_id
    JOIN dwh.dim_track dt
        ON fil.track_id = dt.track_id
    GROUP BY
        vcsr.country,
        vcsr.country_group,
        dt.genre_name,
        vcsr.total_sales_usd
),
final_genre_analysis AS (
    SELECT
        *,
        ROUND(genre_sales_usd / NULLIF(total_sales_usd, 0) * 100, 2) AS genre_percent_of_sales,
        RANK() OVER (PARTITION BY country ORDER BY genre_sales_usd DESC) AS genre_rank
    FROM country_genre_sales
)
SELECT *
FROM final_genre_analysis
ORDER BY country_group DESC, country, genre_rank;

-- 4. Customer behavior by country group
WITH customer_stats AS (
    SELECT
        dc.customer_id,
        dc.country,
        COUNT(fi.invoice_id) AS order_count,
        COALESCE(SUM(fi.total_usd), 0) AS customer_revenue_usd
    FROM dwh.dim_customer dc
    LEFT JOIN dwh.fact_invoice fi
        ON dc.customer_id = fi.customer_id
    GROUP BY dc.customer_id, dc.country
),
customer_country_groups AS (
    SELECT
        country,
        CASE
            WHEN COUNT(customer_id) = 1 THEN 'Other'
            ELSE country
        END AS country_group
    FROM customer_stats
    GROUP BY country
)
SELECT
    ccg.country_group,
    COUNT(cs.customer_id) AS customers_count,
    ROUND(AVG(cs.order_count), 2) AS avg_orders_per_customer,
    ROUND(AVG(cs.customer_revenue_usd), 2) AS avg_revenue_per_customer_usd
FROM customer_stats cs
JOIN customer_country_groups ccg
    ON cs.country = ccg.country
GROUP BY ccg.country_group
ORDER BY customers_count DESC;

-- 5. Employee yearly sales growth
WITH employee_year_sales AS (
    SELECT
        de.employee_id,
        de.first_name,
        de.last_name,
        de.years_employed,
        EXTRACT(YEAR FROM fi.invoice_date)::int AS sales_year,
        COUNT(DISTINCT fi.customer_id) AS served_clients,
        COALESCE(SUM(fi.total_usd), 0) AS sales_amount_usd
    FROM dwh.dim_employee de
    LEFT JOIN dwh.dim_customer dc
        ON de.employee_id = dc.support_rep_id
    LEFT JOIN dwh.fact_invoice fi
        ON dc.customer_id = fi.customer_id
    WHERE fi.invoice_date IS NOT NULL
    GROUP BY
        de.employee_id,
        de.first_name,
        de.last_name,
        de.years_employed,
        EXTRACT(YEAR FROM fi.invoice_date)
),
employee_sales_growth AS (
    SELECT
        *,
        sales_year - 1 AS previous_sales_year,
        LAG(sales_amount_usd) OVER (PARTITION BY employee_id ORDER BY sales_year) AS previous_year_sales_usd
    FROM employee_year_sales
)
SELECT
    *,
    ROUND((sales_amount_usd - previous_year_sales_usd) / NULLIF(previous_year_sales_usd, 0) * 100, 2) AS percent_growth
FROM employee_sales_growth
ORDER BY employee_id, sales_year;

-- 6. Extra analysis: year-over-year revenue growth by music genre in ILS
WITH genre_year_sales AS (
    SELECT
        dt.genre_id,
        dt.genre_name,
        EXTRACT(YEAR FROM fi.invoice_date)::int AS sales_year,
        SUM(fil.total_ils) AS genre_sales_ils
    FROM dwh.fact_invoice_line fil
    JOIN dwh.fact_invoice fi
        ON fil.invoice_id = fi.invoice_id
    JOIN dwh.dim_track dt
        ON dt.track_id = fil.track_id
    GROUP BY
        dt.genre_id,
        dt.genre_name,
        EXTRACT(YEAR FROM fi.invoice_date)
),
 genre_sales_growth AS (
    SELECT
        *,
        sales_year - 1 AS previous_sales_year,
        LAG(genre_sales_ils) OVER (PARTITION BY genre_id ORDER BY sales_year) AS previous_year_sales_ils
    FROM genre_year_sales
)
SELECT
    *,
    ROUND((genre_sales_ils - previous_year_sales_ils) / NULLIF(previous_year_sales_ils, 0) * 100, 2) AS percent_growth
FROM genre_sales_growth
ORDER BY genre_name, sales_year;
