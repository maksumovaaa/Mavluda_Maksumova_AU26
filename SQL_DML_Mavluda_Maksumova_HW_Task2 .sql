-- SQL_DML_Mavluda_Maksumova_HW_Task2.sql
-- Task 2: DELETE vs VACUUM FULL vs TRUNCATE.
-- How to run in DBeaver: autocommit must be ON (Auto in the toolbar).
-- Run the queries ONE BY ONE (put the cursor inside the query and press Ctrl+Enter),
-- not the whole file with Alt+X. After each step I write the time and the size in the
-- lines with ____ below.


-- Step 1. Create the table with 10 million rows
DROP TABLE IF EXISTS public.table_to_delete;

CREATE TABLE public.table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1, (10^7)::int) x;


-- Step 2. Space of the table (the query from the task)
SELECT *, pg_size_pretty(total_bytes) AS total,
          pg_size_pretty(index_bytes) AS INDEX,
          pg_size_pretty(toast_bytes) AS toast,
          pg_size_pretty(table_bytes) AS TABLE
FROM (SELECT *, total_bytes - index_bytes - COALESCE(toast_bytes, 0) AS table_bytes
      FROM (SELECT c.oid, nspname AS table_schema,
                   relname AS TABLE_NAME,
                   c.reltuples AS row_estimate,
                   pg_total_relation_size(c.oid) AS total_bytes,
                   pg_indexes_size(c.oid) AS index_bytes,
                   pg_total_relation_size(reltoastrelid) AS toast_bytes
            FROM pg_class c
            LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE relkind = 'r') a) a
WHERE table_name LIKE '%table_to_delete%';
-- Result: total = ____


-- Step 3. DELETE of 1/3 of the rows
-- 3a. DELETE (the time is shown in DBeaver after the query finishes)
DELETE FROM public.table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string', '')::int % 3 = 0;
-- Result: time = ____ sec

-- 3b. Space after DELETE (I run the same query from Step 2 again, or this short one)
SELECT pg_size_pretty(pg_total_relation_size('public.table_to_delete')) AS total_size;
-- Result: total = ____

-- 3c. VACUUM FULL (in DBeaver press Ctrl+Shift+O to see the output)
VACUUM FULL VERBOSE public.table_to_delete;
-- Result: time = ____ sec

-- 3d. Space after VACUUM FULL
SELECT pg_size_pretty(pg_total_relation_size('public.table_to_delete')) AS total_size;
-- Result: total = ____

-- 3e. Recreate the table
DROP TABLE IF EXISTS public.table_to_delete;

CREATE TABLE public.table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1, (10^7)::int) x;


-- Step 4. TRUNCATE
-- 4a. TRUNCATE
TRUNCATE public.table_to_delete;
-- Result: time = ____ sec

-- 4c. Space after TRUNCATE
SELECT pg_size_pretty(pg_total_relation_size('public.table_to_delete')) AS total_size;
-- Result: total = ____


-- Step 5. Conclusions
-- 5a. Space of the table:
--     after CREATE ____ / after DELETE ____ / after VACUUM FULL ____ / after TRUNCATE ____
--
-- 5b. DELETE vs TRUNCATE
--   Time: DELETE is slow because it checks and removes rows one by one (about 3.3
--         million rows). TRUNCATE takes milliseconds because it does not look at rows.
--   Disk space: DELETE does not make the table file smaller. TRUNCATE removes the file
--         data and the space is free at once.
--   Transaction: DELETE writes every removed row to the log (WAL) and leaves dead rows.
--         TRUNCATE writes almost nothing, but it locks the whole table
--         (ACCESS EXCLUSIVE) and has no WHERE, it removes all rows.
--   Rollback: in PostgreSQL both can be rolled back inside BEGIN ... ROLLBACK. In
--         autocommit mode each query is saved at once, so rollback is not possible
--         after it finished.
--
-- 5c. Explanations
--   Why DELETE does not free space immediately:
--     PostgreSQL uses MVCC. DELETE only marks rows as dead, because other transactions
--     can still need them. Dead rows stay in the table file, so the size is the same.
--     A normal VACUUM lets new rows reuse this space but does not shrink the file.
--   Why VACUUM FULL changes the size:
--     It writes a new copy of the table with only living rows and removes the old file,
--     so the table becomes smaller (about 1/3 here). It locks the table and needs extra
--     disk space while it works.
--   Why TRUNCATE is different:
--     It does not delete rows one by one. It creates a new empty file for the table and
--     drops the old one, so there are no dead rows and VACUUM is not needed.
--   Performance and storage:
--     A big DELETE is slow, creates a lot of WAL and table bloat (dead rows), and
--     queries scan more pages until VACUUM FULL. TRUNCATE is the fastest way to empty a
--     table, but only if I need to remove ALL rows.
