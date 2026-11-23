-- SQL_DDL_Func_HW (tasks 1-5), dvd_rental
-- The script can be run many times (I use CREATE OR REPLACE and IF NOT EXISTS).

CREATE SCHEMA IF NOT EXISTS core;

------------------------------------------------------------
-- TASK 1. View: sales_revenue_by_category_qtr
------------------------------------------------------------
-- Current quarter: date_trunc('quarter', current_date) gives the first day of
--   the current quarter. The quarter ends 3 months after that day.
-- Current year: the same date already has the year, so the same quarter
--   of another year does not match.
-- Revenue: sum of payment.amount for each category.
-- Why only categories with sales appear: the query starts from payment and
--   uses JOINs, so a category without payments gets no row.
-- Zero-sales categories are also removed by HAVING SUM(amount) > 0.
-- Dynamic: current_date changes by itself, so when a new quarter starts
--   the view uses the new quarter automatically.
-- How I checked it: the database has data only for 2007, so the view is empty
--   today. I ran the function from Task 2 with a 2007 date and compared the
--   result with a manual SUM on the payment table.
-- Data that should NOT appear: payments from other quarters or years, and
--   categories with no sales in the current quarter.
CREATE OR REPLACE VIEW public.sales_revenue_by_category_qtr AS
SELECT c.name AS category,
       SUM(p.amount) AS total_revenue
FROM payment p
JOIN rental r         ON r.rental_id = p.rental_id
JOIN inventory i      ON i.inventory_id = r.inventory_id
JOIN film_category fc ON fc.film_id = i.film_id
JOIN category c       ON c.category_id = fc.category_id
WHERE p.payment_date >= date_trunc('quarter', current_date)
  AND p.payment_date <  date_trunc('quarter', current_date) + INTERVAL '3 months'
GROUP BY c.name
HAVING SUM(p.amount) > 0;

-- Test: returns 0 rows today (no data in the current year)
SELECT * FROM public.sales_revenue_by_category_qtr;

------------------------------------------------------------
-- TASK 2. Function: get_sales_revenue_by_category_qtr
------------------------------------------------------------
-- Why a parameter is needed: the view uses only today's date. With a
--   parameter I can check any quarter and year (for example 2007).
--   The quarter and year are taken from the given date. Default is today.
-- Invalid quarter: there is no separate quarter number, so a wrong quarter
--   like 5 cannot be passed. A wrong date text ('2007-13-45') gives a normal
--   PostgreSQL error.
-- NULL date: comparisons with NULL are not true, so 0 rows are returned.
--   (A SQL function cannot use RAISE.)
-- No data: the result is empty, no error.
CREATE OR REPLACE FUNCTION public.get_sales_revenue_by_category_qtr(p_date date DEFAULT current_date)
RETURNS TABLE (category text, total_revenue numeric)
LANGUAGE sql
AS $$
    SELECT c.name::text,
           SUM(p.amount)
    FROM payment p
    JOIN rental r         ON r.rental_id = p.rental_id
    JOIN inventory i      ON i.inventory_id = r.inventory_id
    JOIN film_category fc ON fc.film_id = i.film_id
    JOIN category c       ON c.category_id = fc.category_id
    WHERE p.payment_date >= date_trunc('quarter', p_date)
      AND p.payment_date <  date_trunc('quarter', p_date) + INTERVAL '3 months'
    GROUP BY c.name
    HAVING SUM(p.amount) > 0
    ORDER BY c.name;
$$;

-- Test 1: quarter with data
SELECT * FROM public.get_sales_revenue_by_category_qtr('2007-02-15');
-- Test 2: quarter without data - empty result
SELECT * FROM public.get_sales_revenue_by_category_qtr('2030-01-01');
-- Test 3: NULL - empty result
SELECT * FROM public.get_sales_revenue_by_category_qtr(NULL);

------------------------------------------------------------
-- TASK 3. core.most_popular_films_by_countries
------------------------------------------------------------
-- "Most popular" = the film with the most rentals (count of rows in rental)
--   made by customers who live in that country. I did not use revenue,
--   because an expensive film could win with only a few rentals.
-- Country of a customer: customer -> address -> city -> country.
-- Ties: I use RANK(), so if two films have the same number of rentals,
--   both are returned.
-- Country with no data (or wrong name): the country is still returned, but
--   film, rating, language, length and release_year are NULL.
--   Names are compared in lower case, so 'brazil' also works.
-- NULL or empty array: RAISE EXCEPTION.
CREATE OR REPLACE FUNCTION core.most_popular_films_by_countries(p_countries text[])
RETURNS TABLE (country text, film text, rating text, language text, length int, release_year int)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
BEGIN
    IF p_countries IS NULL OR array_length(p_countries, 1) IS NULL THEN
        RAISE EXCEPTION 'Country list must not be NULL or empty';
    END IF;

    RETURN QUERY
    WITH input AS (
        SELECT DISTINCT trim(x) AS country_name
        FROM unnest(p_countries) AS x
    ),
    counts AS (
        SELECT co.country AS country_name,
               i.film_id,
               COUNT(*) AS rentals
        FROM rental r
        JOIN customer cu  ON cu.customer_id = r.customer_id
        JOIN address a    ON a.address_id = cu.address_id
        JOIN city ci      ON ci.city_id = a.city_id
        JOIN country co   ON co.country_id = ci.country_id
        JOIN inventory i  ON i.inventory_id = r.inventory_id
        GROUP BY co.country, i.film_id
    ),
    ranked AS (
        SELECT cn.country_name, cn.film_id,
               RANK() OVER (PARTITION BY cn.country_name ORDER BY cn.rentals DESC) AS rnk
        FROM counts cn
    )
    SELECT inp.country_name::text,
           f.title::text,
           f.rating::text,
           l.name::text,
           f.length::int,
           f.release_year::int
    FROM input inp
    LEFT JOIN ranked rk  ON lower(rk.country_name) = lower(inp.country_name) AND rk.rnk = 1
    LEFT JOIN film f     ON f.film_id = rk.film_id
    LEFT JOIN language l ON l.language_id = f.language_id
    ORDER BY inp.country_name, f.title;
END;
$$;

-- Test 1: normal use
SELECT * FROM core.most_popular_films_by_countries(ARRAY['Afghanistan','Brazil','United States']);
-- Test 2: country that is not in the database - film is NULL
SELECT * FROM core.most_popular_films_by_countries(ARRAY['Atlantis']);
-- Test 3: empty array - exception (uncomment to try)
-- SELECT * FROM core.most_popular_films_by_countries(ARRAY[]::text[]);

------------------------------------------------------------
-- TASK 4. core.films_in_stock_by_title
------------------------------------------------------------
-- Pattern matching: the user gives the pattern, for example '%love%'.
--   % means any number of any characters, _ means one character.
--   '%love%' finds titles that have the word love in any place.
-- Case sensitivity: I use ILIKE, so LOVE, Love and love are the same.
-- "In stock": the film has at least one copy that is not rented out now
--   (there is no rental with return_date IS NULL for this copy).
-- Performance: the slowest part is f.title ILIKE '%...%'. The pattern starts
--   with %, so a normal index cannot be used and the whole film table is
--   scanned (a pg_trgm index could help). The rest is light: films are
--   filtered first, EXISTS stops at the first free copy, and the last rental
--   is taken only for matching films (LIMIT 1).
-- Multiple matches: all films are returned, row_num is 1, 2, 3 ... by title.
-- No matches: one row with a "not found" message.
-- NULL or empty pattern: RAISE EXCEPTION.
CREATE OR REPLACE FUNCTION core.films_in_stock_by_title(p_title text)
RETURNS TABLE (row_num int, film_title text, language text, customer_name text, rental_date timestamp)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
BEGIN
    IF p_title IS NULL OR trim(p_title) = '' THEN
        RAISE EXCEPTION 'Title pattern must not be NULL or empty';
    END IF;

    RETURN QUERY
    SELECT (ROW_NUMBER() OVER (ORDER BY f.title))::int,
           f.title::text,
           l.name::text,
           (cu.first_name || ' ' || cu.last_name)::text,
           lr.rental_date::timestamp
    FROM film f
    JOIN language l ON l.language_id = f.language_id
    LEFT JOIN LATERAL (
        SELECT r.rental_date, r.customer_id
        FROM rental r
        JOIN inventory i2 ON i2.inventory_id = r.inventory_id
        WHERE i2.film_id = f.film_id
        ORDER BY r.rental_date DESC
        LIMIT 1
    ) lr ON TRUE
    LEFT JOIN customer cu ON cu.customer_id = lr.customer_id
    WHERE f.title ILIKE p_title
      AND EXISTS (
            SELECT 1
            FROM inventory i
            WHERE i.film_id = f.film_id
              AND NOT EXISTS (SELECT 1 FROM rental r2
                              WHERE r2.inventory_id = i.inventory_id
                                AND r2.return_date IS NULL)
          )
    ORDER BY f.title;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 1, ('Film with title ' || p_title || ' was not found in stock')::text,
                            NULL::text, NULL::text, NULL::timestamp;
    END IF;
END;
$$;

-- Test 1: normal use
SELECT * FROM core.films_in_stock_by_title('%love%');
-- Test 2: nothing matches - message row
SELECT * FROM core.films_in_stock_by_title('%zzzzqqq%');
-- Test 3: NULL - exception (uncomment to try)
-- SELECT * FROM core.films_in_stock_by_title(NULL);

------------------------------------------------------------
-- TASK 5. new_movie
------------------------------------------------------------
-- The language Klingon is not in the default database, so I add it first
-- (only if it does not exist yet).
INSERT INTO language (name)
SELECT 'Klingon'
WHERE NOT EXISTS (SELECT 1 FROM language WHERE lower(name) = 'klingon');

-- Unique ID: I do not write the id myself. film_id has a sequence as its
--   default value, so PostgreSQL gives the next number. I did not use MAX()+1,
--   because it fails when two users insert at the same time.
--   The new id is returned with RETURNING.
-- No duplicates: before INSERT I check lower(title) in the film table.
-- If the movie already exists: RAISE EXCEPTION and nothing is inserted.
-- Language check: I look for language_id by name in the language table.
--   If it is not found, RAISE EXCEPTION. The id is not hardcoded.
-- If the insert fails: the EXCEPTION block catches the error and raises it
--   again with a clear message. The function runs in one transaction, so
--   no half-saved data is left.
-- Consistency: rental_rate 4.99, rental_duration 3 and replacement_cost 19.99
--   are set inside the function, and language_id comes from the language
--   table, so the foreign key is always valid.
-- Optional parameters: release year (default is the current year) and
--   language (default is Klingon).
CREATE OR REPLACE FUNCTION public.new_movie(
    p_title text,
    p_release_year int DEFAULT extract(year FROM current_date)::int,
    p_language text DEFAULT 'Klingon')
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
    v_language_id int;
    v_film_id int;
BEGIN
    IF p_title IS NULL OR trim(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title must not be NULL or empty';
    END IF;

    SELECT language_id INTO v_language_id
    FROM language
    WHERE lower(name) = lower(trim(p_language));

    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'Language % does not exist in the language table', p_language;
    END IF;

    IF EXISTS (SELECT 1 FROM film WHERE lower(title) = lower(trim(p_title))) THEN
        RAISE EXCEPTION 'Movie with title % already exists', p_title;
    END IF;

    BEGIN
        INSERT INTO film (title, release_year, language_id, rental_duration, rental_rate, replacement_cost)
        VALUES (trim(p_title), p_release_year, v_language_id, 3, 4.99, 19.99)
        RETURNING film_id INTO v_film_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Insert of movie % failed: %', p_title, SQLERRM;
    END;

    RETURN v_film_id;
END;
$$;

-- Test 1: default year and language
SELECT public.new_movie('My Test Movie');
-- Test 2: own year and language
SELECT public.new_movie('My Test Movie 2', 2020, 'English');
-- Test 3: same title again - exception (uncomment to try)
-- SELECT public.new_movie('My Test Movie');
-- Test 4: language that does not exist - exception (uncomment to try)
-- SELECT public.new_movie('Another Movie', 2020, 'Martian');

-- Remove the test rows so the script can be run again:
DELETE FROM film WHERE title IN ('My Test Movie', 'My Test Movie 2');
