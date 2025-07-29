# Heap

What we'll survey:
- heap
- execution plan
- cache

## Database implementation

Why don't we use CSV files on S3 buckets ?

You can't use a database without index, why ?
Because access would be slow, why ?
Because data should be read on fs, which is 10⁵ slower that memory, why ?
Because it can't fit in memory, why ?
Because huge amount of data today

## Table is heap

There is several data structures in database to store data:
- "heap-organized" table, also called heap;
- "index-organized" table, also called IOT;
- "hash-cluster" table.

We usually refer "heap-organized" table, and this is the only storage available in PostgreSQL.

What is a heap ?
It is not [the usual definition](https://stackoverflow.com/questions/1699057/why-are-two-different-concepts-both-called-heap) 
It is rather an area of storage which is unsorted (as in laundry heap).

heap = large random-access files
random-access = sequential access
random-access <> index access

you had to read 
- the whole table if you want to find all record matching a criteria
- unless you know there is one record only (it is unique), but you may end up reading the whole table

Algorithmic complexity is in the N order - O(n)


## Create a table

Create table
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
```

## How is a table stored ?

Each table is stored in a different file; when table grows, more file are created.

> Each table is stored in a separate file (named after the table filenode number, which can be found in pg_class.relfilenode).
> When a table exceeds 1 GB, it is divided into gigabyte-sized segments.
> The first segment's file name is the same as the filenode; subsequent segments are named filenode.1, filenode.2, etc. This arrangement avoids problems on platforms that have file size limitations.
> A table that has columns with potentially large entries will have an associated TOAST table, which is used for out-of-line storage of field values that are too large to keep in the table rows proper.
from [PostgreSQL doc](https://www.postgresql.org/docs/current/storage-file-layout.html)

> PostgreSQL uses a fixed page size (commonly 8 kB), and does not allow tuples to span multiple pages.
> Therefore, it is not possible to store very large field values directly.
> To overcome this limitation, large field values are compressed and/or broken up into multiple physical rows.
> This happens transparently to the user, with only small impact on most of the backend code.
> The technique is affectionately known as TOAST (or “the best thing since sliced bread”, The Oversized-Attribute Storage Technique).
from [PostgreSQL doc](https://www.postgresql.org/docs/current/storage-toast.html)

[More](https://www.interdb.jp/pg/pgsql01/02.html#123-layout-of-files-associated-with-tables-and-indexes)

Find its physical location
```postgresql
SELECT pg_relation_filepath('mytable')
FROM pg_settings WHERE name = 'data_directory';
```
base/5/16392


Get file size
```shell
just storage
ls -lh base/5/16392
```
-rw------- 1 postgres postgres 0 Jul 29 07:37 base/5/16392

The file is empty (0 bytes)

## Create a row

Add data
```postgresql
INSERT INTO mytable (id) VALUES (-1);
SELECT * FROM mytable;
```

Get file size again
```shell
ls -lh base/5/16392
```
-rw------- 1 postgres postgres 8192 Jul 29 07:40 base/5/16392

The file is 8192, why ?

## How is a row stored ?

PostgreSQL allocate space in filesystem in chunks to improver performance :
- several rows will be written;
- allocate space (writing a file) require a system call which is expensive.

These chunks are called blocks, their size is 8 kBytes = 8 * 1 024 bytes = 8 192 bytes.

Rows are stored in these blocks.
Rows are also called tuples or items.

A row can have a variable length (e.g. text), only its content is stored : NULL values does not store any content.
To be able to access variable-length rows quickly, in an indexed way, we should use pointers.
To save more space, as we can't know how many rows will be stored:
- pointer are stored at block's start;
- rows are stored at block's end.

PostgreSQL need to access row quickly internally (e.g. for indexes) and can't use the row primary key (it may not exist).
So it use an internal identifier. But to save even more space, we may need to move row in the block without updating this internal identifier.

How can we do that ? We recall the fundamental theorem of software engineering
> We can solve any problem by introducing an extra level of indirection

We'll use a pointer to pointer :
- row adresses are hidden;
- block pointer expose an identifier called Currrent Tuple IDentifier (CTID);
- its syntax is `(block_number, row_number)` e.g. `(0, 1)`.

```postgresql
SELECT id, ctid
FROM mytable
WHERE 1=1
    AND id = 1
    AND ctid = '(0,1)'
```          

> Every table is stored as an array of blocks.
> All the blocks are logically equivalent, so a particular item (row) can be stored in any blocks.
> The first 24 bytes of each page consists of a block header.
> Following are item identifiers, the rows themselves are stored in space allocated backwards from the end of unallocated space.
> Because an item identifier is never moved until it is freed, its index can be used on a long-term basis to reference an item.
> Every pointer to an item created by PostgreSQL consists of a page number and the index of an item identifier.
[PostgreSQL docs](https://www.postgresql.org/docs/current/storage-page-layout.html#STORAGE-TUPLE-LAYOUT)

[More](https://www.interdb.jp/pg/pgsql01/03.html)

## Create many rows

Add many rows: 10 million (last 40 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT 2
FROM generate_series(1, 10000000) AS n;
```

Check what happened on disk
```shell
ls -l base/5/16392
```
-rw------- 1 postgres postgres 346M Jul 29 08:37 base/5/16385

The data has been written to disk, 346 MB

Check logs
```text
2025-07-29 08:37:16.187 UTC [27] LOG:  checkpoint starting: wal
```

## Get size easily

If we want to know the size without connecting to container fs, can call this function
```postgresql
SELECT pg_table_size('mytable') table_block_count
```
362 586 112 blocks

Convert to size using `pg_size_pretty`
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size
```
346 MB

How many rows ?
```postgresql
SELECT
   stt.relname                        table_name
   ,stt.n_live_tup                    row_count
FROM pg_stat_user_tables stt
WHERE 1=1
   AND relname = 'mytable'
;
```

## Access rows and get table usage 

Query first 10 rows of table
```postgresql
SELECT id 
FROM mytable
LIMIT 10
```

You can know how the table has been accessed
```postgresql
SELECT
     'events:'
     ,stt.n_tup_ins                     insert_count
     ,stt.n_tup_upd + stt.n_tup_hot_upd update_count
     ,stt.n_tup_del                     delete_count
     ,stt.last_seq_scan                 last_read
     ,stt.seq_tup_read                  rows_read_count
--,stt.*
FROM pg_stat_user_tables stt
WHERE 1=1
  AND relname = 'mytable'
;
```
| ?column? | insert\_count | update\_count | delete\_count | last\_read                        | rows\_read\_count |
|:---------|:--------------|:--------------|:--------------|:----------------------------------|:------------------|
| events:  | 10000001      | 0             | 0             | 2025-07-29 08:55:55.281912 +00:00 | 10                |


Trigger events and check they appear
```postgresql
UPDATE mytable 
SET id = 1
WHERE id = -1;
```

Delete a non-existent row
```postgresql
DELETE FROM mytable
WHERE id = -1;
```
No delete is accounted for

Delete an existing row
```postgresql
DELETE FROM mytable
WHERE id = 1;
```

Delete all rows
```postgresql
DELETE FROM mytable WHERE true
```

Check size
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size
```
Still 346 MB

Check size on disk: it is still there.
```text
-rw------- 1 postgres postgres 346M Jul 29 09:07 base/5/16395
```

But of course you can't access it
```postgresql
SELECT *
FROM mytable
```

You can actually give back the disk space to OS 
```postgresql
TRUNCATE TABLE mytable
```

Check size on disk: it is now empty
```text
-rw------- 1 postgres postgres 0 Jul 29 08:54 base/5/16385
```

Check size
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size
```
0 bytes


You can also reset these stats (but not in production)
```postgresql
SELECT pg_stat_reset_single_table_counters('mytable'::regclass);
```

## How database actually access data ?

Let's start afresh.
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (autovacuum_enabled = FALSE);

INSERT INTO mytable (id) VALUES (-1);
```

You can get execution plan, what is expected to happen
```postgresql
EXPLAIN
SELECT id 
FROM mytable
```

We get
```text
Seq Scan on mytable  (cost=0.00..35.50 rows=2550 width=4)
```

Let's decode it
```text
$operation on $object  (cost=$first_row..$last_row rows=$row_count    $width)
Seq Scan   on mytable  (cost=0.00..35.50           rows=2550          width=4)
```

So:
- operation : `Seq scan`, stands for sequential scan
- object    : `mytable` table; it can be an index, a partition
- cost      : `0` for the first row, then `35` for all following 
- row count : `2 500` rows are expected to be returned from scan 
- width     : each result returned will be around `4` bytes  

The cost is arbitrary

Why do we have 2 550 rows expected ?

Update query-planner statistics
```postgresql
ANALYZE VERBOSE mytable;
```

We get
```text
Seq Scan on mytable  (cost=0.00..35.50 rows=2550 width=4)
```

Run again
```postgresql
EXPLAIN
SELECT id 
FROM mytable
```

This time, we got the right estimate
```text
Seq Scan on mytable  (cost=0.00..1.01 rows=1 width=4)
```

We can get actual rows and timings by executing query with `ANALYZE` option 
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
```

We get
```text
Seq Scan on mytable  (cost=0.00..1.01 rows=1 width=4) (actual time=0.011..0.013 rows=1 loops=1)
```

Let's decode it
```text
$operation on $object  ($expected)                      (actual time=$first_row..$last_row rows=$row_count loops=$loops)
Seq Scan on mytable    (cost=0.00..1.01 rows=1 width=4) (actual time=0.011..0.013          rows=1          loops=1)
```

So:
- time      : `0.011` ms for the first row, then `0.013` for all following
- row count : `1` row was returned from scan
- loops     : the operation has been done  `1` time


We also get two additional lines
```text
Planning Time: 0.036 ms
Execution Time: 0.026 ms
```

We can see the planning time exceed the access time


Add many rows: 10 million (last 40 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT 2
FROM generate_series(1, 10000000) AS n;

ANALYZE mytable;
```


Run again
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
```

The figures are quite different.
```text
Seq Scan on mytable  (cost=0.00..144247.79 rows=9999979 width=4) (actual time=0.015..1031.529 rows=10000001 loops=1)
Planning Time: 0.077 ms
Execution Time: 2180.771 ms
```

The estimation has increased: the cost went from <1 to 44k, because 10 millions rows are expected.
The execution now last 2 seconds, much more than planning time.  


Run again
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
LIMIT 1
```

## Predicate and filter

Query table with predicate
```postgresql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id 
FROM mytable
WHERE id=1
```

```text
Seq Scan on mytable  (cost=0.00..1.01 rows=1 width=4) (actual time=0.017..0.017 rows=0 loops=1)
  Filter: (id = 1)
  Rows Removed by Filter: 1
  Buffers: shared hit=1
Planning Time: 0.095 ms
Execution Time: 0.034 ms
```

It shows up as a filter 
```text
  Filter: (id = 1)
  Rows Removed by Filter: 1
```

Add data (10 million - 40 seconds) 
```postgresql
INSERT INTO mytable (id)
SELECT 2
FROM generate_series(1, 10000000) AS n;
```

Query table
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
WHERE id = -1
```

```text
Seq Scan on mytable  (cost=0.00..44801.10 rows=1 width=4) (actual time=943.653..943.654 rows=1 loops=1)
  Filter: (id = 1)
  Rows Removed by Filter: 10000000
Planning Time: 0.048 ms
Execution Time: 943.688 ms
```

We still have 1 row expected and 1 row actual
What about querying on value 2 ?

Query table
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
WHERE id = 2
```

It expects
```text
Seq Scan on mytable  (cost=0.00..169248.60 rows=10000048 width=4) (actual time=26.939..1169.128 rows=10000000 loops=1)
Filter: (id = 2)
Rows Removed by Filter: 1
```




Query table
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
WHERE id = -1
```






Let's update statistics
```postgresql
ANALYZE VERBOSE mytable;
```

Query table
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
WHERE id = 1
```
## Data distribution

Query-planner statistics
```postgresql
SELECT
     s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
    ,s.correlation       correlation_column_block_order 
    ,s.avg_width         size_bytes   
    ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
--     ,'pg_stats'
    ,s.*
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'id'
```
No statistics

Query table
```postgresql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, ctid 
FROM mytable
```

Query table : aggregation
```postgresql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, COUNT(1) 
FROM mytable
GROUP BY id 
ORDER BY COUNT(1) DESC 
```

We want :
- 10 % 1
- 40 % 2
- 50 % 3

```postgresql
INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 10/100 * 1000) AS n;
    
INSERT INTO mytable (id)
SELECT 2
FROM generate_series(1, 40/100 * 1000) AS n;

INSERT INTO mytable (id)
SELECT NULL
FROM generate_series(1, 50/100 * 1000) AS n;
```

Statistics
```postgresql
ANALYZE VERBOSE mytable;
```

Query-planner statistics
```postgresql
SELECT
     s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
    ,s.correlation       correlation_column_block_order 
    ,s.avg_width         size_bytes   
    ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
--     ,'pg_stats'
    ,s.*
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'id'
```

