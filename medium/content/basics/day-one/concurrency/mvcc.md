## What if we do not commit ?

We use implicit COMMIT till now. What if we use explicit COMMIT, that is, we start a transaction ?

### INSERT without COMMIT

PostgreSQL by default use AUTOCOMMIT feature.

What happens if we insert rows, without committing ?
Will they be stored on disk ?

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

BEGIN TRANSACTION;

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
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
FROM generate_series(1, 10000000) AS n;
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
- when a vacuum is executed, if all rows in a block are visible to all transactions, the block is  written in the visibility map, which is a separate file.

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
TRUNCATE TABLE mytable
````

Monitor you disk I/O
```shell
iostat --human 2 | awk 'BEGIN {print "Size(R - W)"} /$DEVICE/  {print $6  " - " $7}'
```

Add many rows: 100 million (last 40 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 100000000) AS n;
```

You get a lot of writes, which is expected
```text
Size(R - W)
60,7M - 612,1M
58,6M - 575,8M
61,1M - 590,5M
60,1M - 576,6M
60,1M - 585,0M
31,8M - 338,9M
0,0k - 8,2M
```

The table is huge
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size
```
3 GB

Now access all rows
```postgresql
SELECT COUNT(*)
FROM mytable
```

You've got as much write than read, this is about setting hint bits
```text
Size(R - W)
0,0k - 324,0k
84,5M - 45,3M
713,8M - 721,6M
737,3M - 727,3M
726,5M - 754,2M
737,6M - 719,5M
330,6M - 321,4M
0,0k - 1,2M
0,0k - 1008,0k
```

Reference: PostgreSQL Internals, Part I - Isolation and MVCC / Page and tuples / Operations on tuples / Commit

### Setting all_visible in visibility map on VACUUM

````postgresql
TRUNCATE TABLE mytable
````

Add many rows: 10 million (last 40 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
```

```postgresql
ANALYZE VERBOSE mytable
```

Visibility map for a table
```postgresql
SELECT
   relpages       block_count          -- Number of pages
   ,relallvisible  all_visible_block_count   -- Number of pages that are visible to all transactions
FROM pg_class
WHERE 1=1
    AND relname = 'mytable'
    --AND relpages <> 0
;
```

| block\_count | all\_visible\_block\_count |
|:-------------|:---------------------------|
| 44248        | 0                          |


```postgresql
VACUUM VERBOSE mytable
```

Visibility map for a table
```postgresql
SELECT
   relpages       block_count          
   ,relallvisible  all_visible_block_count 
   ,TRUNC(relallvisible / relpages) * 100 || ' %' pct_visible
FROM pg_class
WHERE 1=1
    AND relname = 'mytable'
    --AND relpages <> 0
;
```

| block\_count | all\_visible\_block\_count | pct\_visible |
|:-------------|:---------------------------|:-------------|
| 44248        | 44248                      | 100 %        |


```postgresql
SELECT relpages block_count
FROM pg_class WHERE relname = 'mytable';
```

[Reference](https://www.cybertec-postgresql.com/en/speeding-up-things-with-hint-bits/)

### Mark row version as dead on SELECT

AKA Page pruning.

Now you know that PostgreSQL is optimized for few writes, many read. What if you  update the same row many times ? It will create many versions, and older ones will be discarded quickly. 

That means several things:
- the size of your table will keep growing;
- therefore any sequential scan will take longer;
- unless you do some VACUUM, but VACUUM use resources (CPU and I/O) and cause contention (lock).

What can you do to mitigate that ?
You can use a feature call fillfactor to keep some space in the block for row's update, so that UPDATE create the version in the same block. When a SELECT read a block which does not have enough free space, it checks if the versions in the block are still visible. If not, it marks these versions as dead.

Therefore, an UPDATE with happens afterward on the block can use the space of the dead version to create a new version: you didn't have to trigger a VACUUM on the whole table and you have its benefits.

There is even more: all live versions in blocks are moved to the end, allowing for a single continuous free space at the beginning: no fragmentation.

Need a fill factor < 100% and update rows several times (INSERT doesn't work)


 But pointer to tuples are not removed, because they may be referenced by indexes (move this to index section ?)

Reference: PostgreSQL Internals, Part I - Isolation and MVCC / Page pruning


## Beware of long-running transaction

Until now, we only dealt with one table, but transaction encompass all tables.
At higher isolation level than default, consistency is extended beyond the duration of a single statement and encompass the whole transaction. Therefore, even rows that have been deleted on ta ble T by a commited transaction should be kept for another still-running transaction, which may access T in the future. That means vacuuming is deffered until this transaction ends.

At the worst, if the transaction keep on for hours or days, the database may allocate more and more disk space, only to handle updates.

> There is only one horizon for the whole database, so if it is being held by a transaction, it is impossible to vacuum any data within this horizon—even if this data has not been accessed by this transaction.

> • If a transaction (no matter whether it is real or virtual) at the Repeatable Read
or Serializable isolation level is running for a long time, it thereby holds the
database horizon and defers vacuuming.
• A real transaction at the Read Committed isolation level holds the database
horizon in the same way, even if it is not executing any operators (being in the
“idle in transaction” state).

Reference: PostgreSQL Internals, Part I - Isolation and MVCC / Snapshot