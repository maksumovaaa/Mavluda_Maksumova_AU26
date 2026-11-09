-- SQL_DML_HW | Task 2: DELETE vs TRUNCATE
-- Run each block one by one and write down the numbers you get
-- (replace the "???" in the report at the bottom with your own results)

------------------------------------------------------------
-- 0. Create the table with 10 million rows
------------------------------------------------------------
CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1, (10^7)::int) AS x;

-- space of the table at the start
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete')) AS size_before_delete,
       pg_total_relation_size('table_to_delete') AS size_bytes;

------------------------------------------------------------
-- 3. DELETE
------------------------------------------------------------
DELETE FROM table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string', '')::int % 3 = 0; -- removes 1/3 of all rows

-- a) time of DELETE: look at the execution time that DBeaver shows
--    (or run "\timing" in psql before the DELETE)

-- b) space after DELETE
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete')) AS size_after_delete,
       pg_total_relation_size('table_to_delete') AS size_bytes;

-- extra check: dead tuples that are still inside the table
SELECT n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'table_to_delete';

-- c) VACUUM FULL (in DBeaver press Ctrl+Shift+O to see the output)
VACUUM FULL VERBOSE table_to_delete;

-- d) space after VACUUM FULL
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete')) AS size_after_vacuum_full,
       pg_total_relation_size('table_to_delete') AS size_bytes;

-- e) recreate the table
DROP TABLE table_to_delete;

CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1, (10^7)::int) AS x;

SELECT pg_size_pretty(pg_total_relation_size('table_to_delete')) AS size_after_recreate;

------------------------------------------------------------
-- 4. TRUNCATE
------------------------------------------------------------
TRUNCATE table_to_delete;

-- a) time of TRUNCATE: again check the execution time in DBeaver

-- c) space after TRUNCATE
SELECT pg_size_pretty(pg_total_relation_size('table_to_delete')) AS size_after_truncate,
       pg_total_relation_size('table_to_delete') AS size_bytes;

------------------------------------------------------------
-- 5. REPORT
------------------------------------------------------------

-- a) Space consumption of table_to_delete
--    | step                  | size  |
--    |-----------------------|-------|
--    | after creation        | ???   |
--    | after DELETE          | ???   |   (almost the same as before)
--    | after VACUUM FULL     | ???   |   (about 1/3 smaller)
--    | after recreate        | ???   |
--    | after TRUNCATE        | ???   |   (almost 0)

-- b) DELETE vs TRUNCATE
--    Execution time:
--      DELETE took ??? sec, TRUNCATE took ??? sec. DELETE is much slower because
--      it checks the condition for every row and marks each row as deleted one by one.
--      TRUNCATE does not look at rows at all, it just throws away the table files.
--    Disk space:
--      After DELETE the size stays almost the same. After TRUNCATE the space
--      is given back to the OS right away.
--    Transaction behavior:
--      DELETE writes every deleted row to the WAL, and it can have a WHERE condition.
--      TRUNCATE removes all rows at once, has no WHERE, and writes very little to the log.
--    Rollback:
--      Both can be rolled back in PostgreSQL if they are inside a transaction
--      (BEGIN ... ROLLBACK). TRUNCATE is also transactional in Postgres,
--      but it takes a strong ACCESS EXCLUSIVE lock on the table.

-- c) Explanations
--    Why DELETE does not free space immediately:
--      PostgreSQL uses MVCC. A deleted row is not physically removed, it is only
--      marked as dead (dead tuple), because other transactions may still need
--      to see it. The pages stay in the file, so the table size does not change.
--      Normal VACUUM / autovacuum can reuse this space inside the table, but
--      it usually does not return it to the operating system.
--
--    Why VACUUM FULL changes table size:
--      VACUUM FULL rewrites the whole table into a new file and copies only live rows.
--      Dead tuples are left behind, so the new file is smaller and the
--      old file is deleted. The downside: it locks the table completely
--      while it works and can take a long time.
--
--    Why TRUNCATE behaves differently:
--      TRUNCATE does not work row by row. It removes the old data file and
--      creates a new empty one, so it is very fast and the space is freed
--      at once. No dead tuples are left, so no VACUUM is needed.
--
--    How they affect performance and storage:
--      DELETE on a big table is slow, creates a lot of WAL and dead tuples, and
--      needs VACUUM later, so the table can get bloated. VACUUM FULL gives space
--      back but blocks the table. TRUNCATE is the fastest and cleanest way to
--      empty a table, but only when we want to delete ALL rows.
--      Conclusion: use DELETE for part of the rows, TRUNCATE for all rows.
