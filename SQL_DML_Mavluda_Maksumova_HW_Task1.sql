-- SQL_DML_Mavluda_Maksumova_HW_Task1.sql
-- Task 1: add my favorite films, actors and inventory, change one customer to me,
-- then rent the films and pay for them.
--
-- My 3 films (different years and genres):
--   The Shawshank Redemption - 1994 - Drama     - 4.99  - 1 week
--   Interstellar             - 2014 - Sci-Fi    - 9.99  - 2 weeks
--   Spirited Away            - 2001 - Animation - 19.99 - 3 weeks
--
-- General notes (they are true for every subtask below):
-- * Each subtask is a separate transaction (BEGIN ... COMMIT). If one of them fails,
--   only that subtask is rolled back and nothing from it is saved. The subtasks that
--   were already committed stay in the database, so I can fix the error and run the
--   script again from the failed place.
-- * Before COMMIT I can still write ROLLBACK and the changes of this subtask
--   disappear. After COMMIT rollback is not possible any more.
-- * I use INSERT ... SELECT instead of INSERT ... VALUES because the ids (language_id,
--   film_id, actor_id, store_id ...) are taken from the real tables by joins, so I don't
--   hardcode them. It also lets me add the row only if it does not exist yet.
-- * The script can be run many times: every INSERT has WHERE NOT EXISTS (or ON CONFLICT),
--   so no duplicates appear.
-- * Referential integrity: every foreign key value comes from a SELECT on the parent
--   table, so a child row can't point to a missing parent. Order of work: film and actor
--   first, then film_actor and inventory, then rental, then payment.
-- * last_update = CURRENT_DATE for all new and updated rows. The payment table has no
--   last_update column, so there it is not used.


-- 1. Add the films -------------------------------------------------------------
-- Uniqueness: a film is added only if there is no film with the same title (any case).
-- language_id is found by name 'English', rental_duration is in days (7, 14, 21).
BEGIN;

INSERT INTO public.film (title, description, release_year, language_id, rental_duration,
                         rental_rate, length, replacement_cost, rating, last_update)
SELECT v.title,
       v.description,
       v.release_year,
       l.language_id,
       v.rental_duration,
       v.rental_rate,
       v.length,
       v.replacement_cost,
       v.rating::public.mpaa_rating,
       CURRENT_DATE
FROM (VALUES
        ('The Shawshank Redemption', 'Two imprisoned men become friends and find hope over many years.', 1994, 7, 4.99, 142, 19.99, 'R'),
        ('Interstellar', 'A team of explorers travels through a wormhole to save humanity.', 2014, 14, 9.99, 169, 24.99, 'PG-13'),
        ('Spirited Away', 'A ten-year-old girl enters a world of spirits and tries to save her parents.', 2001, 21, 19.99, 125, 14.99, 'PG')
     ) AS v (title, description, release_year, rental_duration, rental_rate, length, replacement_cost, rating)
CROSS JOIN public.language AS l
WHERE UPPER(l.name) = 'ENGLISH'
  AND NOT EXISTS (SELECT 1
                  FROM public.film AS f
                  WHERE UPPER(f.title) = UPPER(v.title))
RETURNING film_id, title, release_year, rental_duration, rental_rate;

COMMIT;


-- 2. Add the actors (6 real actors) --------------------------------------------
-- Uniqueness: actor has no unique key on the name, so I check first_name + last_name
-- with NOT EXISTS (names in the table are in upper case, so I compare in upper case).
-- If the actor is already in the table, he is not added again.
BEGIN;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT v.first_name,
       v.last_name,
       CURRENT_DATE
FROM (VALUES
        ('TIM', 'ROBBINS'),
        ('MORGAN', 'FREEMAN'),
        ('MATTHEW', 'MCCONAUGHEY'),
        ('ANNE', 'HATHAWAY'),
        ('RUMI', 'HIIRAGI'),
        ('MIYU', 'IRINO')
     ) AS v (first_name, last_name)
WHERE NOT EXISTS (SELECT 1
                  FROM public.actor AS a
                  WHERE UPPER(a.first_name) = v.first_name
                    AND UPPER(a.last_name) = v.last_name)
RETURNING actor_id, first_name, last_name;

COMMIT;


-- 3. Connect actors with films (film_actor) ------------------------------------
-- Relationships: actor_id and film_id are found by joining actor and film on names,
-- so the pair always points to existing rows. Duplicates: the primary key is
-- (actor_id, film_id), plus NOT EXISTS and ON CONFLICT DO NOTHING.
BEGIN;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id,
       f.film_id,
       CURRENT_DATE
FROM (VALUES
        ('TIM', 'ROBBINS', 'THE SHAWSHANK REDEMPTION'),
        ('MORGAN', 'FREEMAN', 'THE SHAWSHANK REDEMPTION'),
        ('MATTHEW', 'MCCONAUGHEY', 'INTERSTELLAR'),
        ('ANNE', 'HATHAWAY', 'INTERSTELLAR'),
        ('RUMI', 'HIIRAGI', 'SPIRITED AWAY'),
        ('MIYU', 'IRINO', 'SPIRITED AWAY')
     ) AS v (first_name, last_name, title)
INNER JOIN public.actor AS a
    ON UPPER(a.first_name) = v.first_name
   AND UPPER(a.last_name) = v.last_name
INNER JOIN public.film AS f
    ON UPPER(f.title) = v.title
WHERE NOT EXISTS (SELECT 1
                  FROM public.film_actor AS fa
                  WHERE fa.actor_id = a.actor_id
                    AND fa.film_id = f.film_id)
ON CONFLICT (actor_id, film_id) DO NOTHING
RETURNING actor_id, film_id;

COMMIT;


-- 4. Add the films to the inventory --------------------------------------------
-- I take the store with the smallest store_id (not hardcoded). A copy is added only if
-- this film is not in this store yet. film_id comes from the film table by title.
BEGIN;

INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT f.film_id,
       s.store_id,
       CURRENT_DATE
FROM public.film AS f
CROSS JOIN (SELECT store_id
            FROM public.store
            ORDER BY store_id
            LIMIT 1) AS s
WHERE UPPER(f.title) IN ('THE SHAWSHANK REDEMPTION', 'INTERSTELLAR', 'SPIRITED AWAY')
  AND NOT EXISTS (SELECT 1
                  FROM public.inventory AS i
                  WHERE i.film_id = f.film_id
                    AND i.store_id = s.store_id)
RETURNING inventory_id, film_id, store_id;

COMMIT;


-- 5. Change an existing customer to my data ------------------------------------
-- The customer must have at least 43 rentals and 43 payments. I take the one with the
-- smallest customer_id. The address table is NOT changed, I only use an existing
-- address_id. The NOT EXISTS part is for re-running: when I am already in the table
-- (after the first run my old rentals are deleted, so another customer could be chosen),
-- nothing is updated.
-- Check before the update (which customer will be changed):
--   SELECT c.customer_id, c.first_name, c.last_name
--   FROM public.customer AS c
--   WHERE (SELECT COUNT(*) FROM public.rental AS r WHERE r.customer_id = c.customer_id) >= 43
--     AND (SELECT COUNT(*) FROM public.payment AS p WHERE p.customer_id = c.customer_id) >= 43
--   ORDER BY c.customer_id
--   LIMIT 1;
BEGIN;

UPDATE public.customer
SET first_name = 'MAVLUDA',
    last_name = 'MAKSUMOVA',
    email = 'mavluda.maksumova@sakilacustomer.org',
    address_id = (SELECT a.address_id
                  FROM public.address AS a
                  ORDER BY a.address_id
                  LIMIT 1),
    last_update = CURRENT_DATE
WHERE customer_id = (SELECT c.customer_id
                     FROM public.customer AS c
                     WHERE (SELECT COUNT(*) FROM public.rental AS r WHERE r.customer_id = c.customer_id) >= 43
                       AND (SELECT COUNT(*) FROM public.payment AS p WHERE p.customer_id = c.customer_id) >= 43
                     ORDER BY c.customer_id
                     LIMIT 1)
  AND NOT EXISTS (SELECT 1
                  FROM public.customer AS m
                  WHERE UPPER(m.first_name) = 'MAVLUDA'
                    AND UPPER(m.last_name) = 'MAKSUMOVA')
RETURNING customer_id, first_name, last_name, email, address_id, last_update;

COMMIT;


-- 6. Delete my old rentals and payments ----------------------------------------
-- Why it is safe:
--  * only rows of ONE customer (found by my name) are deleted, other customers are not
--    touched;
--  * payment is deleted first, then rental, because payment has a foreign key to rental;
--  * customer and inventory are not touched: other customers still rent from the same
--    inventory, and I need the customer row itself.
-- How I made sure nothing extra is lost: I ran the SELECT below before the delete and
-- compared the numbers with the RETURNING results.
--   SELECT (SELECT COUNT(*) FROM public.payment WHERE customer_id = c.customer_id) AS payments,
--          (SELECT COUNT(*) FROM public.rental WHERE customer_id = c.customer_id) AS rentals
--   FROM public.customer AS c
--   WHERE UPPER(c.first_name) = 'MAVLUDA' AND UPPER(c.last_name) = 'MAKSUMOVA';
-- If something fails in the middle, the whole transaction is rolled back, so I can't get
-- a state where payments are deleted but rentals are not.
BEGIN;

DELETE FROM public.payment
WHERE customer_id IN (SELECT c.customer_id
                      FROM public.customer AS c
                      WHERE UPPER(c.first_name) = 'MAVLUDA'
                        AND UPPER(c.last_name) = 'MAKSUMOVA')
RETURNING payment_id, rental_id;

DELETE FROM public.rental
WHERE customer_id IN (SELECT c.customer_id
                      FROM public.customer AS c
                      WHERE UPPER(c.first_name) = 'MAVLUDA'
                        AND UPPER(c.last_name) = 'MAKSUMOVA')
RETURNING rental_id, inventory_id;

COMMIT;


-- 7. Rent my films ---------------------------------------------------------------
-- inventory_id comes from inventory (film found by title), customer_id from my customer
-- row, staff_id is any staff member of the same store as the copy. Duplicates: a rental
-- is added only if this customer has not rented this copy yet.
-- Dates are in the first half of 2017 (so they fit the payment partitions).
BEGIN;

INSERT INTO public.rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT TIMESTAMP '2017-03-10 12:00:00',
       i.inventory_id,
       c.customer_id,
       TIMESTAMP '2017-03-10 12:00:00' + f.rental_duration * INTERVAL '1 day',
       (SELECT s.staff_id
        FROM public.staff AS s
        WHERE s.store_id = i.store_id
        ORDER BY s.staff_id
        LIMIT 1),
       CURRENT_DATE
FROM public.customer AS c
CROSS JOIN public.inventory AS i
INNER JOIN public.film AS f
    ON f.film_id = i.film_id
WHERE UPPER(c.first_name) = 'MAVLUDA'
  AND UPPER(c.last_name) = 'MAKSUMOVA'
  AND UPPER(f.title) IN ('THE SHAWSHANK REDEMPTION', 'INTERSTELLAR', 'SPIRITED AWAY')
  AND NOT EXISTS (SELECT 1
                  FROM public.rental AS r
                  WHERE r.inventory_id = i.inventory_id
                    AND r.customer_id = c.customer_id)
RETURNING rental_id, inventory_id, customer_id, rental_date, return_date;

COMMIT;


-- 8. Pay for the rentals ---------------------------------------------------------
-- The amount is the rental_rate of the film. rental_id, customer_id and staff_id are
-- taken from the rental I just created, so the payment is linked to a real rental.
-- Duplicates: a payment is added only if the rental has no payment yet.
-- payment_date is in the first half of 2017 (partition exists for these dates).
BEGIN;

INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT r.customer_id,
       r.staff_id,
       r.rental_id,
       f.rental_rate,
       TIMESTAMP '2017-03-10 12:05:00'
FROM public.rental AS r
INNER JOIN public.customer AS c
    ON c.customer_id = r.customer_id
INNER JOIN public.inventory AS i
    ON i.inventory_id = r.inventory_id
INNER JOIN public.film AS f
    ON f.film_id = i.film_id
WHERE UPPER(c.first_name) = 'MAVLUDA'
  AND UPPER(c.last_name) = 'MAKSUMOVA'
  AND UPPER(f.title) IN ('THE SHAWSHANK REDEMPTION', 'INTERSTELLAR', 'SPIRITED AWAY')
  AND NOT EXISTS (SELECT 1
                  FROM public.payment AS p
                  WHERE p.rental_id = r.rental_id)
RETURNING payment_id, customer_id, rental_id, amount, payment_date;

COMMIT;
