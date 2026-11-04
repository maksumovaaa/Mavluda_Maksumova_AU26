
-- PART 1, TASK 1
-- Show all animation movies released during 2017-2019 with rate more than 1,
-- sorted alphabetically.
-- Assumptions: rate = rental_rate; 2017 and 2019 are included; sorted by title.

SELECT f.title, f.release_year, f.rental_rate
FROM public.film AS f
INNER JOIN public.film_category AS fc ON fc.film_id = f.film_id
INNER JOIN public.category AS c ON c.category_id = fc.category_id
WHERE UPPER(c.name) = 'ANIMATION'
  AND f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
ORDER BY f.title;

SELECT f.title, f.release_year, f.rental_rate
FROM public.film AS f
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
  AND f.film_id IN (SELECT fc.film_id
                    FROM public.film_category AS fc
                    WHERE fc.category_id IN (SELECT c.category_id
                                             FROM public.category AS c
                                             WHERE UPPER(c.name) = 'ANIMATION'))
ORDER BY f.title;

WITH animation_films AS (
    SELECT fc.film_id
    FROM public.film_category AS fc
    INNER JOIN public.category AS c ON c.category_id = fc.category_id
    WHERE UPPER(c.name) = 'ANIMATION'
)
SELECT f.title, f.release_year, f.rental_rate
FROM public.film AS f
INNER JOIN animation_films AS af ON af.film_id = f.film_id
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
ORDER BY f.title;

-- PART 1, TASK 2
-- Calculate the revenue earned by each rental store after March 2017 (since April)

SELECT TRIM(a.address || ' ' || COALESCE(a.address2, '')) AS store_address,
       SUM(p.amount) AS revenue
FROM public.payment AS p
INNER JOIN public.rental AS r ON r.rental_id = p.rental_id
INNER JOIN public.inventory AS i ON i.inventory_id = r.inventory_id
INNER JOIN public.store AS s ON s.store_id = i.store_id
INNER JOIN public.address AS a ON a.address_id = s.address_id
WHERE p.payment_date >= '2017-04-01'
GROUP BY s.store_id, a.address, a.address2
ORDER BY revenue DESC;

SELECT TRIM(a.address || ' ' || COALESCE(a.address2, '')) AS store_address,
       (SELECT SUM(p.amount)
        FROM public.payment AS p
        INNER JOIN public.rental AS r ON r.rental_id = p.rental_id
        INNER JOIN public.inventory AS i ON i.inventory_id = r.inventory_id
        WHERE i.store_id = s.store_id
          AND p.payment_date >= '2017-04-01') AS revenue
FROM public.store AS s
INNER JOIN public.address AS a ON a.address_id = s.address_id
ORDER BY revenue DESC NULLS LAST;

WITH store_revenue AS (
    SELECT i.store_id, SUM(p.amount) AS revenue
    FROM public.payment AS p
    INNER JOIN public.rental AS r ON r.rental_id = p.rental_id
    INNER JOIN public.inventory AS i ON i.inventory_id = r.inventory_id
    WHERE p.payment_date >= '2017-04-01'
    GROUP BY i.store_id
)
SELECT TRIM(a.address || ' ' || COALESCE(a.address2, '')) AS store_address,
       sr.revenue
FROM store_revenue AS sr
INNER JOIN public.store AS s ON s.store_id = sr.store_id
INNER JOIN public.address AS a ON a.address_id = s.address_id
ORDER BY sr.revenue DESC;
-- PART 1, TASK 3
-- Show top-5 actors by number of movies (released since 2015) they took part in

SELECT a.first_name, a.last_name, COUNT(f.film_id) AS number_of_movies
FROM public.actor AS a
INNER JOIN public.film_actor AS fa ON fa.actor_id = a.actor_id
INNER JOIN public.film AS f ON f.film_id = fa.film_id
WHERE f.release_year >= 2015
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY number_of_movies DESC, a.last_name, a.first_name
LIMIT 5;

SELECT a.first_name,
       a.last_name,
       (SELECT COUNT(*)
        FROM public.film_actor AS fa
        INNER JOIN public.film AS f ON f.film_id = fa.film_id
        WHERE fa.actor_id = a.actor_id
          AND f.release_year >= 2015) AS number_of_movies
FROM public.actor AS a
ORDER BY number_of_movies DESC, a.last_name, a.first_name
LIMIT 5;

WITH actor_movies AS (
    SELECT fa.actor_id, COUNT(f.film_id) AS number_of_movies
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f ON f.film_id = fa.film_id
    WHERE f.release_year >= 2015
    GROUP BY fa.actor_id
)
SELECT a.first_name, a.last_name, am.number_of_movies
FROM actor_movies AS am
INNER JOIN public.actor AS a ON a.actor_id = am.actor_id
ORDER BY am.number_of_movies DESC, a.last_name, a.first_name
LIMIT 5;

-- PART 1, TASK 4
-- Show number of Drama, Travel, Documentary per year (columns: release_year,
-- number_of_drama_movies, number_of_travel_movies, number_of_documentary_movies),
-- sorted by release year in descending order. 

SELECT f.release_year,
       COUNT(CASE WHEN UPPER(c.name) = 'DRAMA' THEN 1 END)       AS number_of_drama_movies,
       COUNT(CASE WHEN UPPER(c.name) = 'TRAVEL' THEN 1 END)      AS number_of_travel_movies,
       COUNT(CASE WHEN UPPER(c.name) = 'DOCUMENTARY' THEN 1 END) AS number_of_documentary_movies
FROM public.film AS f
INNER JOIN public.film_category AS fc ON fc.film_id = f.film_id
INNER JOIN public.category AS c ON c.category_id = fc.category_id
WHERE UPPER(c.name) IN ('DRAMA', 'TRAVEL', 'DOCUMENTARY')
GROUP BY f.release_year
ORDER BY f.release_year DESC;

SELECT t.release_year,
       COUNT(CASE WHEN t.genre = 'DRAMA' THEN 1 END)       AS number_of_drama_movies,
       COUNT(CASE WHEN t.genre = 'TRAVEL' THEN 1 END)      AS number_of_travel_movies,
       COUNT(CASE WHEN t.genre = 'DOCUMENTARY' THEN 1 END) AS number_of_documentary_movies
FROM (SELECT f.release_year, UPPER(c.name) AS genre
      FROM public.film AS f
      INNER JOIN public.film_category AS fc ON fc.film_id = f.film_id
      INNER JOIN public.category AS c ON c.category_id = fc.category_id
      WHERE UPPER(c.name) IN ('DRAMA', 'TRAVEL', 'DOCUMENTARY')) AS t
GROUP BY t.release_year
ORDER BY t.release_year DESC;

WITH genre_films AS (
    SELECT f.release_year, UPPER(c.name) AS genre
    FROM public.film AS f
    INNER JOIN public.film_category AS fc ON fc.film_id = f.film_id
    INNER JOIN public.category AS c ON c.category_id = fc.category_id
    WHERE UPPER(c.name) IN ('DRAMA', 'TRAVEL', 'DOCUMENTARY')
)
SELECT gf.release_year,
       COUNT(CASE WHEN gf.genre = 'DRAMA' THEN 1 END)       AS number_of_drama_movies,
       COUNT(CASE WHEN gf.genre = 'TRAVEL' THEN 1 END)      AS number_of_travel_movies,
       COUNT(CASE WHEN gf.genre = 'DOCUMENTARY' THEN 1 END) AS number_of_documentary_movies
FROM genre_films AS gf
GROUP BY gf.release_year
ORDER BY gf.release_year DESC;

-- PART 2, TASK 1
-- Which three employees generated the most revenue in 2017?

SELECT s.first_name, s.last_name, s.store_id, SUM(p.amount) AS revenue
FROM public.staff AS s
INNER JOIN public.payment AS p ON p.staff_id = s.staff_id
WHERE p.payment_date >= '2017-01-01'
  AND p.payment_date < '2018-01-01'
GROUP BY s.staff_id, s.first_name, s.last_name, s.store_id
ORDER BY revenue DESC
LIMIT 3;

SELECT s.first_name,
       s.last_name,
       (SELECT MAX(i.store_id)
        FROM public.payment AS p
        INNER JOIN public.rental AS r ON r.rental_id = p.rental_id
        INNER JOIN public.inventory AS i ON i.inventory_id = r.inventory_id
        WHERE p.staff_id = s.staff_id
          AND p.payment_date = (SELECT MAX(p2.payment_date)
                                FROM public.payment AS p2
                                WHERE p2.staff_id = s.staff_id
                                  AND p2.payment_date >= '2017-01-01'
                                  AND p2.payment_date < '2018-01-01')) AS last_store_id,
       (SELECT SUM(p3.amount)
        FROM public.payment AS p3
        WHERE p3.staff_id = s.staff_id
          AND p3.payment_date >= '2017-01-01'
          AND p3.payment_date < '2018-01-01') AS revenue
FROM public.staff AS s
ORDER BY revenue DESC NULLS LAST
LIMIT 3;

WITH staff_revenue AS (
    SELECT p.staff_id, SUM(p.amount) AS revenue, MAX(p.payment_date) AS last_payment_date
    FROM public.payment AS p
    WHERE p.payment_date >= '2017-01-01'
      AND p.payment_date < '2018-01-01'
    GROUP BY p.staff_id
),
last_store AS (
    SELECT p.staff_id, MAX(i.store_id) AS store_id
    FROM public.payment AS p
    INNER JOIN staff_revenue AS sr
            ON sr.staff_id = p.staff_id AND sr.last_payment_date = p.payment_date
    INNER JOIN public.rental AS r ON r.rental_id = p.rental_id
    INNER JOIN public.inventory AS i ON i.inventory_id = r.inventory_id
    GROUP BY p.staff_id
)
SELECT s.first_name, s.last_name, ls.store_id AS last_store_id, sr.revenue
FROM staff_revenue AS sr
INNER JOIN public.staff AS s ON s.staff_id = sr.staff_id
INNER JOIN last_store AS ls ON ls.staff_id = sr.staff_id
ORDER BY sr.revenue DESC
LIMIT 3;

-- PART 2, TASK 2
-- Show which 5 movies were rented more than others (number of rentals), and what's the
-- expected age of the audience for these movies? Use the MPAA film rating system.

SELECT f.title,
       f.rating,
       CASE f.rating
            WHEN 'G' THEN 'All ages'
            WHEN 'PG' THEN '8+'
            WHEN 'PG-13' THEN '13+'
            WHEN 'R' THEN '17+'
            WHEN 'NC-17' THEN '18+'
            ELSE 'Unknown'
       END AS expected_audience_age,
       COUNT(r.rental_id) AS number_of_rentals
FROM public.film AS f
INNER JOIN public.inventory AS i ON i.film_id = f.film_id
INNER JOIN public.rental AS r ON r.inventory_id = i.inventory_id
GROUP BY f.film_id, f.title, f.rating
ORDER BY number_of_rentals DESC, f.title
LIMIT 5;

SELECT f.title,
       f.rating,
       CASE f.rating
            WHEN 'G' THEN 'All ages'
            WHEN 'PG' THEN '8+'
            WHEN 'PG-13' THEN '13+'
            WHEN 'R' THEN '17+'
            WHEN 'NC-17' THEN '18+'
            ELSE 'Unknown'
       END AS expected_audience_age,
       (SELECT COUNT(r.rental_id)
        FROM public.inventory AS i
        INNER JOIN public.rental AS r ON r.inventory_id = i.inventory_id
        WHERE i.film_id = f.film_id) AS number_of_rentals
FROM public.film AS f
ORDER BY number_of_rentals DESC, f.title
LIMIT 5;

WITH film_rentals AS (
    SELECT i.film_id, COUNT(r.rental_id) AS number_of_rentals
    FROM public.inventory AS i
    INNER JOIN public.rental AS r ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
)
SELECT f.title,
       f.rating,
       CASE f.rating
            WHEN 'G' THEN 'All ages'
            WHEN 'PG' THEN '8+'
            WHEN 'PG-13' THEN '13+'
            WHEN 'R' THEN '17+'
            WHEN 'NC-17' THEN '18+'
            ELSE 'Unknown'
       END AS expected_audience_age,
       fr.number_of_rentals
FROM film_rentals AS fr
INNER JOIN public.film AS f ON f.film_id = fr.film_id
ORDER BY fr.number_of_rentals DESC, f.title
LIMIT 5;

-- PART 3, V1
-- Which actors/actresses didn't act for a longer period of time than the others?

SELECT a.first_name,
       a.last_name,
       MAX(f.release_year) AS latest_release_year,
       EXTRACT(YEAR FROM CURRENT_DATE) - MAX(f.release_year) AS gap_years
FROM public.actor AS a
INNER JOIN public.film_actor AS fa ON fa.actor_id = a.actor_id
INNER JOIN public.film AS f ON f.film_id = fa.film_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY gap_years DESC, a.last_name, a.first_name;

SELECT a.first_name,
       a.last_name,
       t.latest_release_year,
       EXTRACT(YEAR FROM CURRENT_DATE) - t.latest_release_year AS gap_years
FROM public.actor AS a
INNER JOIN (SELECT fa.actor_id, MAX(f.release_year) AS latest_release_year
            FROM public.film_actor AS fa
            INNER JOIN public.film AS f ON f.film_id = fa.film_id
            GROUP BY fa.actor_id) AS t ON t.actor_id = a.actor_id
ORDER BY gap_years DESC, a.last_name, a.first_name;

WITH latest_release AS (
    SELECT fa.actor_id, MAX(f.release_year) AS latest_release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f ON f.film_id = fa.film_id
    GROUP BY fa.actor_id
)
SELECT a.first_name,
       a.last_name,
       lr.latest_release_year,
       EXTRACT(YEAR FROM CURRENT_DATE) - lr.latest_release_year AS gap_years
FROM latest_release AS lr
INNER JOIN public.actor AS a ON a.actor_id = lr.actor_id
ORDER BY gap_years DESC, a.last_name, a.first_name;

-- PART 3, V2
-- V2: gaps between sequential films per each actor.

SELECT a.first_name,
       a.last_name,
       f1.release_year AS year_from,
       MIN(f2.release_year) AS year_to,
       MIN(f2.release_year) - f1.release_year AS gap_years
FROM public.actor AS a
INNER JOIN public.film_actor AS fa1 ON fa1.actor_id = a.actor_id
INNER JOIN public.film AS f1 ON f1.film_id = fa1.film_id
INNER JOIN public.film_actor AS fa2 ON fa2.actor_id = a.actor_id
INNER JOIN public.film AS f2 ON f2.film_id = fa2.film_id
                            AND f2.release_year > f1.release_year
GROUP BY a.actor_id, a.first_name, a.last_name, f1.release_year
ORDER BY gap_years DESC, a.last_name, a.first_name;

SELECT t.first_name,
       t.last_name,
       t.year_from,
       t.year_to,
       t.year_to - t.year_from AS gap_years
FROM (SELECT DISTINCT
             a.actor_id,
             a.first_name,
             a.last_name,
             f1.release_year AS year_from,
             (SELECT MIN(f2.release_year)
              FROM public.film_actor AS fa2
              INNER JOIN public.film AS f2 ON f2.film_id = fa2.film_id
              WHERE fa2.actor_id = a.actor_id
                AND f2.release_year > f1.release_year) AS year_to
      FROM public.actor AS a
      INNER JOIN public.film_actor AS fa1 ON fa1.actor_id = a.actor_id
      INNER JOIN public.film AS f1 ON f1.film_id = fa1.film_id) AS t
WHERE t.year_to IS NOT NULL
ORDER BY gap_years DESC, t.last_name, t.first_name;

WITH actor_years AS (
    SELECT DISTINCT fa.actor_id, f.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f ON f.film_id = fa.film_id
),
year_gaps AS (
    SELECT ay1.actor_id,
           ay1.release_year AS year_from,
           MIN(ay2.release_year) AS year_to
    FROM actor_years AS ay1
    INNER JOIN actor_years AS ay2 ON ay2.actor_id = ay1.actor_id
                                 AND ay2.release_year > ay1.release_year
    GROUP BY ay1.actor_id, ay1.release_year
)
SELECT a.first_name,
       a.last_name,
       MAX(yg.year_to - yg.year_from) AS biggest_gap_years
FROM year_gaps AS yg
INNER JOIN public.actor AS a ON a.actor_id = yg.actor_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY biggest_gap_years DESC, a.last_name, a.first_name;
