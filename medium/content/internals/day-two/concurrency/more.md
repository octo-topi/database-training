# More

## optimizations

### setting hint bits in row version on SELECT

TODO: Pattern cache "stale while revalidate"

To make sure a row is visible to the current transaction, PostgreSQL should get the status of xmin and xmax transactions.

To do so:
- he check if the transaction in finished (it checks if it is still in progress);
- if so, he checks it has been aborted on commited.

Then, he can apply visibility rules.

All these operations takes times. To speed them up, the status of the transaction for xmin and xmax are stored in the row header. They are call 'hint bits', because they help  (hints) getting the visibility rules more quickly, and bits because they are stored in a bit.

These flags are documented in [source code](https://github.com/postgres/postgres/blob/master/src/include/access/htup_details.h).

The hint bits are written the first time the row is read, because at the write time the transaction is still in progress; obviously we can't know if it will commit or rollback.

Let's see hint bits.
```postgresql
SELECT 
    t.t_ctid,
    t_xmin,   
    CASE
         WHEN (t_infomask & 256) > 0 THEN 'commited'
         WHEN (t_infomask & 512) > 0 THEN 'aborted'
         ELSE ''
    END xmin_status,
    t_xmax,
    CASE
         WHEN (t_infomask & 1024) > 0 THEN 'commited'
         WHEN (t_infomask & 2048) > 0 THEN 'aborted'
         ELSE ''
    END  AS xmax_status
FROM heap_page_items(get_raw_page('mytable', 0)) t
ORDER BY lp
```

Therefore, reading a table just after inserting data will cause all blocks which are accessed for the first time to be updated on hint bits. As writing happens on whole block, much I/O will be used. This is the price to pay for fast COMMIT : data is written two times.

This strategy is efficient if you write one time, read many times.
If you create a row, update it frequently, and read it seldomly, you will spend much time writing.

Let's demonstrate this.
First, empty the table.
````postgresql
CHECKPOINT;
TRUNCATE TABLE mytable;
````

Start monitoring you disk I/O
```shell
iostat --human 10 | awk 'BEGIN {print "Size(R - W)"} /$DEVICE/  {print $6  " - " $7}'
```

Add many rows: 10 million (last 4 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
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
Hint bits information is not critical.

```postgresql
SHOW wal_log_hints
```

[wal_long_hints](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-WAL-LOG-HINTS)

Reference: PostgreSQL Internals, Part I - Isolation and MVCC / Page and tuples / Operations on tuples / Commit

### setting all_visible in visibility map on VACUUM

Rows that have been inserted in bulk, and never updated, fill whole blocks.
Visibility checks should be performed on hint bits, for each row.

To optimize access for whole block, a hint bit in the header is written by vacuum.
It is set when all block rows are visible to all transactions.

Let's do it.
````postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
````

Add many rows: 10 million (last 40 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

Check the flag is set to false in the block.
```postgresql
SELECT (flags & 4 > 0) all_rows_visible_in_block
FROM page_header(get_raw_page('mytable', 0))
```

| all\_rows\_visible\_in\_block |
|:------------------------------|
| false                         |



Gather stats
```postgresql
ANALYZE VERBOSE mytable;
```

Check that no blocks are now marked as "all rows are visibles to all transactions".
```postgresql
SELECT
    relpages       block_count               -- Number of pages
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


Let's run a VACUUM.
```postgresql
VACUUM VERBOSE mytable
```

The log mentions
```text
visibility map: 44248 pages set all-visible, 0 pages set all-frozen (0 were all-visible)
```

Check the flag is set to true now
```postgresql
SELECT flags & 4 > 0 all_rows_visible_in_block
FROM page_header(get_raw_page('mytable', 0))
```

| all\_rows\_visible\_in\_block |
|:------------------------------|
| true                          |

Check that all blocks are now marked as "all rows are visibles to all transactions".
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


[Reference](https://www.cybertec-postgresql.com/en/speeding-up-things-with-hint-bits/)

### mark row version as dead on SELECT

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

## mvcc specific files

To speed up row visibility check, there is a visibility map.

To speed up row version insertion, there is a free space map.

On the filesystem, they are stored separately from data.
They have the same name as data file, but prefixes `fsm` and `vm`.

Let's see them.
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;

ANALYZE mytable;
VACUUM mytable;
```

Let's see.
```text
root@8fc4aeb8d887:/var/lib/postgresql/18/docker# ls -ltrh base/16384/16735*
-rw------- 1 postgres postgres 104K Mar 26 07:11 base/16384/16735_fsm
-rw------- 1 postgres postgres  16K Mar 26 07:13 base/16384/16735_vm
-rw------- 1 postgres postgres 346M Mar 26 07:13 base/16384/16735
```

Or, to get their size more quickly.
```postgresql
SELECT 
    pg_size_pretty(pg_relation_size('mytable','main'))  data_size,
    pg_size_pretty(pg_relation_size('mytable','vm'))    vm_size,
    pg_size_pretty(pg_relation_size('mytable','fsm'))   fsm_size
```

Their size is modest according to data size.

| data\_size | vm\_size | fsm\_size |
|:-----------|:---------|:----------|
| 346 MB     | 16 kB    | 104 kB    |
