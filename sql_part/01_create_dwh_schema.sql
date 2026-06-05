-- Chinook Data Warehouse Project
-- File: 01_create_dwh_schema.sql
-- Purpose: Create the DWH schema, dimensions, fact tables and currency conversion columns.
-- Assumption: Raw Chinook tables and additional project tables already exist in the stg schema.

CREATE SCHEMA IF NOT EXISTS dwh;

-- Rebuild DWH objects for repeatable execution
DROP VIEW IF EXISTS dwh.v_country_sales_rankings;
DROP TABLE IF EXISTS dwh.fact_invoice_line;
DROP TABLE IF EXISTS dwh.fact_invoice;
DROP TABLE IF EXISTS dwh.dim_playlist;
DROP TABLE IF EXISTS dwh.dim_employee;
DROP TABLE IF EXISTS dwh.dim_track;
DROP TABLE IF EXISTS dwh.dim_customer;
DROP TABLE IF EXISTS dwh.dim_currency;

-- Currency dimension loaded from external exchange-rate API data
CREATE TABLE dwh.dim_currency AS
SELECT
    requested_date::date AS currency_date,
    from_currency,
    to_currency,
    exchange_rate::numeric AS exchange_rate
FROM stg.currency_rates;

-- Customer dimension
CREATE TABLE dwh.dim_customer AS
SELECT
    customerid AS customer_id,
    INITCAP(firstname) AS first_name,
    INITCAP(lastname) AS last_name,
    company,
    address,
    city,
    state,
    country,
    postalcode AS postal_code,
    phone,
    fax,
    email,
    SPLIT_PART(email, '@', 2) AS email_domain,
    supportrepid AS support_rep_id
FROM stg.customer;

-- Track dimension enriched with album, artist, media type and genre data
CREATE TABLE dwh.dim_track AS
SELECT
    t.trackid AS track_id,
    t.name AS track_name,
    t.albumid AS album_id,
    a.title AS album_title,
    ar.artistid AS artist_id,
    ar.name AS artist_name,
    t.mediatypeid AS media_type_id,
    mt.name AS media_type_name,
    t.genreid AS genre_id,
    g.name AS genre_name,
    t.composer,
    t.milliseconds,
    t.milliseconds / 1000 AS duration_seconds,
    TO_CHAR((t.milliseconds / 1000.0) * INTERVAL '1 second', 'MI:SS') AS duration_mm_ss,
    t.bytes,
    t.unitprice AS unit_price
FROM stg.track t
JOIN stg.album a
    ON t.albumid = a.albumid
JOIN stg.artist ar
    ON a.artistid = ar.artistid
JOIN stg.mediatype mt
    ON t.mediatypeid = mt.mediatypeid
JOIN stg.genre g
    ON t.genreid = g.genreid;

-- Employee dimension enriched with department budget data
CREATE TABLE dwh.dim_employee AS
SELECT
    e.employeeid AS employee_id,
    INITCAP(e.lastname) AS last_name,
    INITCAP(e.firstname) AS first_name,
    e.title,
    e.reportsto AS reports_to,
    e.departmentid AS department_id,
    db.department_name,
    db.budget,
    e.birthdate AS birth_date,
    e.hiredate AS hire_date,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.hiredate)) AS years_employed,
    e.address,
    e.city,
    e.state,
    e.country,
    e.postalcode AS postal_code,
    e.phone,
    e.fax,
    e.email,
    SPLIT_PART(e.email, '@', 2) AS email_domain,
    CASE
        WHEN e.employeeid IN (
            SELECT reportsto
            FROM stg.employee
            WHERE reportsto IS NOT NULL
        ) THEN 1
        ELSE 0
    END AS manager_is
FROM stg.employee e
LEFT JOIN stg.department_budget db
    ON e.departmentid = db.department_id;

-- Playlist dimension with playlist-track relationship
CREATE TABLE dwh.dim_playlist AS
SELECT
    pt.playlistid AS playlist_id,
    pt.trackid AS track_id,
    p.name AS playlist_name
FROM stg.playlisttrack pt
JOIN stg.playlist p
    ON pt.playlistid = p.playlistid;

-- Invoice fact table at invoice grain
CREATE TABLE dwh.fact_invoice AS
SELECT
    i.invoiceid AS invoice_id,
    i.customerid AS customer_id,
    i.invoicedate AS invoice_date,
    i.billingaddress AS billing_address,
    i.billingcity AS billing_city,
    i.billingstate AS billing_state,
    i.billingcountry AS billing_country,
    i.billingpostalcode AS billing_postal_code,
    i.total AS total_usd,
    ROUND(i.total * dc.exchange_rate, 2) AS total_ils
FROM stg.invoice i
LEFT JOIN dwh.dim_currency dc
    ON i.invoicedate::date = dc.currency_date;

-- Invoice line fact table at invoice-line grain
CREATE TABLE dwh.fact_invoice_line AS
SELECT
    il.invoicelineid AS invoice_line_id,
    il.invoiceid AS invoice_id,
    il.trackid AS track_id,
    il.unitprice AS unit_price,
    il.quantity,
    il.unitprice * il.quantity AS total_line,
    ROUND((il.unitprice * il.quantity) * dc.exchange_rate, 2) AS total_ils
FROM stg.invoiceline il
JOIN stg.invoice i
    ON il.invoiceid = i.invoiceid
LEFT JOIN dwh.dim_currency dc
    ON i.invoicedate::date = dc.currency_date;

-- Optional indexes for analytical joins and filtering.
-- The dataset is small, but these indexes reflect common DWH optimization practice.
CREATE INDEX IF NOT EXISTS idx_fact_invoice_customer_id
ON dwh.fact_invoice(customer_id);

CREATE INDEX IF NOT EXISTS idx_fact_invoice_invoice_date
ON dwh.fact_invoice(invoice_date);

CREATE INDEX IF NOT EXISTS idx_fact_invoice_line_invoice_id
ON dwh.fact_invoice_line(invoice_id);

CREATE INDEX IF NOT EXISTS idx_fact_invoice_line_track_id
ON dwh.fact_invoice_line(track_id);

CREATE INDEX IF NOT EXISTS idx_dim_track_track_id
ON dwh.dim_track(track_id);

CREATE INDEX IF NOT EXISTS idx_dim_playlist_track_id
ON dwh.dim_playlist(track_id);
