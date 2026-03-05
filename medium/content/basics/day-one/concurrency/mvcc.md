# Concurrency

## What if we do not commit ?

We use implicit COMMIT till now. What if we use explicit COMMIT, that is, we start a transaction ?

### INSERT without COMMIT

PostgreSQL by default use AUTOCOMMIT feature.

What happens if we insert rows, without committing ?
Will they be stored on disk ?

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE if not exisTS mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

BEGIN TRANSACTION;

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

Check size on disk

Find its physical location
```postgresql
SELECT pg_relation_filepath('mytable')
FROM pg_settings WHERE name = 'data_directory';
```
base/16384/16432


Get file size
```shell
just storage
du -sh base/16384/16432
```
346M	base/16384/16432

Data has been written to disk

What if we decide to not insert rows after all ?
```postgresql
ROLLBACK;

SELECT COUNT(*)
FROM mytable;
```
0

Get file size
```shell
du -sh base/16384/16432
```
346M	base/16384/16432

The file has not been truncated

Are these row considered for reuse ?
```postgresql
SELECT
   stt.relname                        table_name
   ,stt.n_live_tup                    active_row_count
   ,stt.n_dead_tup                    deleted_row_count
FROM pg_stat_user_tables stt
WHERE 1=1
   AND relname = 'mytable'
;
```

| table\_name | active\_row\_count | deleted\_row\_count |
|:------------|:-------------------|:--------------------|
| mytable     | 0                  | 10000000            |


Let's reuse it
```postgresql
VACUUM VERBOSE mytable;

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
```

The file on disk hasn't grown.
```shell
du -sh base/16384/16401
```
346M	base/16384/16432

We can safely say heap is optimized for INSERT as it doesn't wait for the transaction to be commited to write data on disk.

### DELETE without COMMIT

We know the space is reused if the rows were deleted, but what if another transaction still see them ?

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
```

Open two clients side-by-side
```shell
just console
just console
```

Then
```postgresql
-- Terminal 1
BEGIN TRANSACTION;
DELETE FROM mytable WHERE true;

-- Terminal 2
VACUUM VERBOSE mytable;
```

You can see that rows are not considered as deleted, so the space cannot be reused.
```text
tuples: 0 removed, 10000000 remain, 0 are dead but not yet removable
```

### UPDATE

We only deal with row deletion as for now, but what happens if we modify the row instead of deleting it ?

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

Check size on disk

Find its physical location
```postgresql
SELECT pg_relation_filepath('mytable')
FROM pg_settings WHERE name = 'data_directory';
```
base/16384/16450


Get file size
```shell
just storage
du -sh base/16384/16450
```
346M	base/16384/16450

Now, let's update them
```postgresql
UPDATE mytable
SET id = -1 * id
```

What is the file size ?
```shell
just storage
du -sh base/16384/16450
```
692M	base/16384/16450

Look like the update has created as many rows as it updated !

```postgresql
SELECT
   stt.relname                        table_name
   ,stt.n_live_tup                    active_row_count
   ,stt.n_dead_tup                    deleted_row_count
FROM pg_stat_user_tables stt
WHERE 1=1
   AND relname = 'mytable'
;
```

This is what happened, the initial version of the row is considered dead

| table\_name | active\_row\_count | deleted\_row\_count |
|:------------|:-------------------|:--------------------|
| mytable     | 10000000           | 10000000            |

## How does it work ?

### Theory

Multi Version Concurrent Control ?
Each row can be modified, leading to different version.
Each transaction should be able to see a coherent state of the data, one version.
It should not see the modifications done by other transactions if not commited.

PostgreSQL implements MVCC by :
- storing all versions of the row in the table;
- showing to the transaction only the version it can see.

Each version of the row has two attributes:
- the id of the transaction that created the version, xmin;
- the id of the transaction that modified this version, xmax.

These attributes are stored in the version.

In a block, to get only visible rows to a transaction T, PostgreSQL should:
- get the xmin and xmax of each version in the block;
- get the status of these transactions;
- apply the visibility rules.

The visibility rules depends on isolation level, which refer to transaction isolation.
Q: What are the visibility rules are the "Read Commited" isolation level ?

You should see only committed data.

You should not see :
- data not yet commited (transaction in progress);
- data whose transaction has been rolled back.

You can see the version that has already appeared and has not been deleted yet.

We end up with these rules.

| status xmin | status xmax | visible |
|:------------|:------------|:--------|
| in progress |             | no      |
| aborted     |             | no      |
| committed   |             | yes     |
| committed   | in progress | yes     |
| committed   | aborted     | yes     |
| committed   | committed   | no      |

But keep in mind that the current transaction may have modified the data, and can read them again.
In other words, xmin and xmax can equal T.
So we also have to hide the previous version from the transaction itself, which give us more rules.

[Reference](https://www.interdb.jp/pg/pgsql05/06.html)

PostgreSQL keep track of:
- transaction in progress in an array in memory;
- when completed, transaction statuses (commited or aborted) in the CLOG (Commit Log) file.

This operation should be performed each time a block is read, and all blocks should be read in a sequential scan.


### Displaying row versions and hint bits

```postgresql
ROLLBACK;
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
```


Insert a first row
```postgresql
BEGIN TRANSACTION;
SELECT pg_current_xact_id();
--859
INSERT INTO mytable(id) VALUES (0);

SELECT * FROM heap_page('mytable', 0);

COMMIT;

SELECT * FROM heap_page('mytable', 0);
```
| ctid    | state  | xmin | xmax |
|:--------|:-------|:-----|:-----|
| \(0,1\) | normal | 859  | 0 a  |

Update it
```postgresql
BEGIN TRANSACTION;
SELECT pg_current_xact_id();
--860
UPDATE mytable SET id=1 WHERE id=0;
COMMIT;
SELECT * FROM heap_page('mytable', 0);
```
| ctid    | state  | xmin  | xmax |
|:--------|:-------|:------|:-----|
| \(0,1\) | normal | 859 c | 860  |
| \(0,2\) | normal | 860   | 0 a  |


Let's access the table
```postgresql
SELECT *
FROM mytable
```

Pattern cache "stale while revalidate"

The hint bits have been set
```postgresql
SELECT * FROM heap_page('mytable', 0);
```

| ctid    | state  | xmin  | xmax  |
|:--------|:-------|:------|:------|
| \(0,1\) | normal | 859 c | 860 c |
| \(0,2\) | normal | 860 c | 0 a   |


## Optimizations

There is therefore many optimization to skip it:
- the first time the row is read:
   - the status of the transaction for xmin and xmax are stored in the row header;
   - if the row is visible to all transactions, a flag is set on row header;
- when a vacuum is executed, if all rows in a block are visible to all transactions, the block is written in the visibility map, which is a separate file.

We can understand now that MVCC is optimized to write data change quickly:
- changes of table data are written immediately to fs, not waiting for COMMIT;
- to COMMIT, the transaction set a bit in the CLOG;
- to ROLLBACK, the transaction set a bit in the CLOG.

### Setting hint bits in row version on SELECT

Reading a table just after inserting data will cause all blocks which are accessed for the first time to be updated on hint bits. As writing happens on whole block, much I/O will be used. This is the price to pay for fast COMMIT : data is written two times.

This strategy is efficient if you write one time, read many times.
If you create a row, update it frequently, and read it seldomly, you will spend much time writing.

Let's demonstrate this.

````postgresql
CHECKPOINT;
TRUNCATE TABLE mytable
````

Monitor you disk I/O
```shell
iostat --human 10 | awk 'BEGIN {print "Size(R - W)"} /$DEVICE/  {print $6  " - " $7}'
```

Add many rows: 10 million (last 4 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
```

What's table size ?
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size
```
346 MB

You get a lot of writes, which is expected.
But why 1GB, more than table size ?
Because, at least, of WAL files.
```text
Size(R - W)
0,0k - 3,8M
14,0M - 1,3G
156,0k - 20,8M
```

Now access all rows
```postgresql
SELECT COUNT(*)
FROM mytable
```

You've got as much write than read (220Mb), this is about setting hint bits.
```text
Size(R - W)
108,0k - 4,6M
222,1M - 224,7M
0,0k - 3,2M
```
If you wonder why all rows have not been written (346 - 220 = 122)
Try this

```postgresql
CHECKPOINT;
```

The missing 122 Mb are written.
```text
0,0k - 6,3M
0,0k - 126,5M
0,0k - 2,3M
```

If you wonder why no WAL files have been written, this is a configuration. 
HInt bits information is not critical.

```postgresql
SHOW wal_log_hints
```

[wal_long_hints](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-WAL-LOG-HINTS)

Reference: PostgreSQL Internals, Part I - Isolation and MVCC / Page and tuples / Operations on tuples / Commit

## Beware of long-running transaction

You saw in the persistence chapter than VACUUM is useful for deleted rows.
Now you understand why vacuum do much more than this: vacuum free space used by obsolete versions of a row.
A row should not be kept when it has been deleted, but an update in PostgreSQL render a row version obsolete.
If you update a row many times, several time between vacuum, the table will grow steadily, which you may want to avoid. 

Until now, we only dealt with one table, but transaction encompass all tables.

At higher isolation level than default, consistency is extended beyond the duration of a single statement and encompass the whole transaction.Therefore, even rows that have been deleted on table T by a commited transaction should be kept for another still-running transaction, which may access T in the future. That means vacuuming is deffered until this transaction ends.

At the worst, if the transaction keep on for hours or days, the database may allocate more and more disk space, only to handle updates.

> There is only one horizon for the whole database, so if it is being held by a transaction, it is impossible to vacuum any data within this horizon—even if this data has not been accessed by this transaction.

> • If a transaction (no matter whether it is real or virtual) at the Repeatable Read
or Serializable isolation level is running for a long time, it thereby holds the
database horizon and defers vacuuming.
• A real transaction at the Read Committed isolation level holds the database
horizon in the same way, even if it is not executing any operators (being in the
“idle in transaction” state).

Reference: PostgreSQL Internals, Part I - Isolation and MVCC / Snapshot

## Auto-vacuum

### Why is auto-vacuum disabled ?

For pedagogic purposes, we disabled auto-vacuum on the table. 
```postgresql
CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
```

We run it manually.
```postgresql
VACUUM VERBOSE mytable;
```

You shall not do this on production.
Instead, you should make sure auto-vacuum is properly configured and runs. 

The last auto-vacuum run is available in `pg_stat_user_tables`.
```postgresql
SELECT last_autovacuum
FROM pg_stat_user_tables t 
WHERE t.relname = 'mytable'
```

Let's see how to configure it.

### Start on update or delete

These parameters control when autovacuum starts because of update or delete, aka dead tuples:
- autovacuum_naptime : minimum delay between autovacuum - default is one minute
- autovacuum_vacuum_threshold : minimum number of updated or deleted tuples - default : 50
- autovacuum_vacuum_scale_factor : fraction of the table size - default is 0.2 (20% of table size).

In short, by default:
- each minute, if the last autovacuum ended more than a minute ago, the table statistics are queried;
- is there (50 tuples + 20% of the rows of the table) as dead tuples ?
- if yes, start an auto-vacuum.

-- TODO: add defragmentation in VACUUM vs SELECT
+ vacuum_cost_limit
```postgresql
WITH settings AS (
  SELECT 
       current_setting('autovacuum_vacuum_threshold')::INT threshold,
       current_setting('autovacuum_vacuum_scale_factor')::DECIMAL scale_factor
)
SELECT 
    t.n_dead_tup,
    c.reltuples * s.scale_factor + s.threshold triggers_at,
    (t.n_dead_tup::DECIMAL > c.reltuples * s.scale_factor + s.threshold) triggers
FROM pg_class c INNER JOIN pg_stat_user_tables t ON t.relname = c.relname,
     settings s 
WHERE t.relname = 'mytable'
```

| n\_dead\_tup | triggers\_at | triggers |
|:-------------|:-------------|:---------|
| 0            | 200050       | false    |


-- cTIODO: add exemple to se t and get settinsg on tabkle

### Start on insert

These parameters control when autovacuum starts on insert :
- autovacuum_vacuum_insert_threshold : minimum number of inserted tuples - default : 1000
- autovacuum_vacuum_insert_scale_factor :  fraction of the table size - default is 0.2 (20% of table size).

```postgresql
WITH settings AS (
  SELECT 
       current_setting('autovacuum_vacuum_insert_threshold')::INT threshold,
       current_setting('autovacuum_vacuum_insert_scale_factor')::DECIMAL scale_factor
)
SELECT 
    t.n_ins_since_vacuum,
    c.reltuples * s.scale_factor + s.threshold triggers_at,
    (t.n_dead_tup::DECIMAL > c.reltuples * s.scale_factor + s.threshold) triggers
FROM pg_class c INNER JOIN pg_stat_user_tables t ON t.relname = c.relname,
     settings s 
WHERE t.relname = 'mytable'
```

| n\_ins\_since\_vacuum | triggers\_at | triggers |
|:----------------------|:-------------|:---------|
| 1000000               | 201000       | false    |

[Reference](https://www.postgresql.org/docs/current/routine-vacuuming.html)
