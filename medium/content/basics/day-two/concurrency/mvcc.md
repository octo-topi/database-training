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
FROM generate_series(1, 10_000_000) AS n;
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
FROM generate_series(1, 10_000_000) AS n;
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
SELECT * FROM mytable;
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

Check the table size. 
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable')) 
```
346M

Now, let's update them.
```postgresql
UPDATE mytable
SET id = -1 * id
```

What is the table size ?
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable')) 
```
692M

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

### Displaying row versions and version metadata

Let's see the version metadata.

```postgresql
ROLLBACK;
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
```

Insert a first row.
```postgresql
BEGIN TRANSACTION;

SELECT pg_current_xact_id();
--859
INSERT INTO mytable(id) VALUES (0);

COMMIT;
```

xmin and xmax are available out-of-the-box.
```postgresql
SELECT t.ctid, t.xmin, t.xmax FROM mytable t;
```

| ctid    | xmin | xmax |
|:--------|------|:-----|
| \(0,1\) | 859  | 0    |


Update the row
```postgresql
BEGIN TRANSACTION;

SELECT pg_current_xact_id();
--860

UPDATE mytable SET id=1 WHERE id=0;

COMMIT;
``` 

We can only see the new version.
```postgresql
SELECT t.ctid, t.xmin, t.xmax FROM mytable t;
```

| ctid    | xmin | xmax |
|:--------|:-----|:-----|
| \(0,2\) | 860  | 0 a  |


To see the old version, we'll use `pageinspect` extension.
```postgresql
SELECT 
  t.t_ctid, t.t_xmin, t.t_xmax
FROM heap_page_items(get_raw_page('mytable', 0)) t
```

Now you can see both of them.

| ctid    | xmin | xmax |
|:--------|:-----|:-----|
| \(0,1\) | 859  | 860  |
| \(0,2\) | 860  | 0    |

```postgresql
SELECT id 
FROM mytable
```

```postgresql
VACUUM mytable
```


## What does commit and rollback do ?

We can understand now that MVCC is optimized to write data change quickly:
- changes of table data are written immediately to fs, not waiting for COMMIT;
- to COMMIT, the transaction set a bit in the CLOG;
- to ROLLBACK, the transaction set a bit in the CLOG.

This view is simplified, but will get more accurate in the cache and resilience section.

## Make the way for auto-vacuum : long-running transaction

You saw in the persistence chapter than VACUUM is useful for deleted rows.
Maybe you understand that VACUUM does much more than that. He free space used by obsolete versions of a row, versions that nobody can see anymore.

A row should not be kept when it has been deleted : this is clear for all database.
When a row is updated, its old version should not be kept : this is relevant only to PostgreSQL.

The worst case is when you update a row many times, in consecutive commited transactions.

The table will grow steadily, which is not desirable:
- you may not afford the extra storage;
- this will make the table sequential read longer.

To avoid this, you set up your auto-vacuum, but he may not be able to recover space.
Why is that so ? Because he can't clean up row version that are still visible to running transaction.

Until now, we only dealt with one table. Transaction encompass all tables.

At higher isolation level than default, consistency is extended beyond the duration of a single statement and encompass the whole transaction. Therefore, even rows that have been deleted on table T by a commited transaction should be kept for another still-running transaction, which may access T in the future. That means vacuuming is deffered until this transaction ends.

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

TODO: Add TOAST link - as soon as the field is not updated, it can stay the same in the TOAST.
The idea is that such data are write once, read many, never changed.