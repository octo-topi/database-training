# Cache

## OS feature reuse

PostgreSQL use most of the features of the OS :
- each connection is handled by an OS process;
- data is shared between processes using shared memory;
- processed are sending signals to each other.

I/O make no difference : PostgreSQL use the OS to access the filesystem and devices.

## Read a file from OS

When a user process want to read a file:
- a system call is made to the OS;
- the OS find all the blocks where the file is located;
- the OS looks into the cache, a zone in memory, for blocks;
- if the blocks are all there, he returns them to the user process;
- if some blocks are missing, the OS reads them from the device:
  - it puts the blocks in cache;
  - he returns them to the user process.

The OS use a cache because some file are frequently used, and I/O is way slower than memory.

## Read a file for PostgreSQL

This is no different for PostgreSQL: all data that should be read from disk should be asked to the OS. We already know that PostgreSQL store all rows of the table in a file, and how to locate it. 
 
Now, a database will have to read a huge amount of data, say for a sequential scan of a table. As it will ask the OS to do it, the OS will use much of its cache for it, although some built-in features prevent a process to use all the cache for himself.

Let's suppose the query use a filter.
```postgresql
SELECT *
FROM mytable
WHERE id = 1
```

Q: Should all data from the table go through the OS cache and returned to the database, even thought only one row is needed ?

We may think it would be enough to filter out all data before returning it to the database, but we saw the storage format of a database block: the row's fields values cannot be read directly, and the visibility rules should be applied. Therefore, there is no filtering. If the file is 1 GB, 1GB will be returned to the database, even though no rows match the query.

## Blocks, blocks 

All OS, when dealing with filesystems, use a small unit called block, or page, whose size is usually 4kb.
You can't read or write less than this unit from the OS, even if the block size of the disk is smaller.

PostgreSQL use a 8kb block size, which means that 1 block in database is 2 blocks in OS.

There is also device block size, which is smaller than OS block size, usually 512 bytes.


## PostgreSQL own cache

PostgreSQL has the same hypothesis as the OS: some data will be used frequently, for example the `user` table, and I/O is slow, so it is better to use a cache. However, he can't rely on the OS cache, as this cache is used by processes other than the database, reading other file that table file. PostgreSQL has its own cache.

The disadvantage of two caches, database and OS, is that a file (at least a block of a file) may exist in both caches, thus "wasting space". There is no way around it, but for PostgreSQL to do direct I/O, reading by himself.

PostgreSQL store its cache in shared memory, which is accessible to all database processes.
The data is stored "as-is", without being decoded. There is no way to find a row of a table in the cache, if it's dead or to get a row value.

## Reading a table 

All data should go through the cache for you to handle them, but you can't see the cache itself.

However, you can use an extension for exploration purposes.
```postgresql
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
```

Let's create a small table
```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 100000) AS n;
```

Table size is 3 Mb
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size;
```

The cache is empty at startup, let's restart the instance.
```shell
just restart-instance
```

Let's see if the cache is filled using `pg_buffercache_summary` function.
```postgresql
SELECT 
    pg_size_pretty(c.buffers_used   * 8 * 1024::numeric) used,
    pg_size_pretty(c.buffers_unused * 8 * 1024::numeric) free,
    TRUNC(c.usagecount_avg) || ' %' used
FROM pg_buffercache_summary() c;
```

| used    | free   | used |
|:--------|:-------|:-----|
| 1984 kB | 126 MB | 3 %  |


Now what is exactly in the cache ? Query `pg_buffercache` view.

```postgresql
SELECT
    c.relname object_name,
    count(*) AS buffer_count,
    pg_size_pretty(count(*) * 1024 * 8) buffer_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
--    AND c.relname NOT LIKE 'pg_%'
--     AND c.relname = 'mytable'
GROUP BY c.relname
ORDER BY buffer_count DESC
LIMIT 3;
```

| object\_name                          | buffer\_count | buffer\_size |
|:--------------------------------------|:--------------|:-------------|
| pg\_operator                          | 14            | 112 kB       |
| pg\_statistic                         | 14            | 112 kB       |
| pg\_operator\_oprname\_l\_r\_n\_index | 6             | 48 kB        |


We've got a bunch of systems objects. 
Let's filter them out and query our table.
```postgresql
SELECT *
FROM mytable
WHERE 1=1
  AND ctid = '(0,1)'
```

Q: How many blocks will you get ?
```postgresql
SELECT
    c.relname object_name,
    count(*) AS buffer_count,
    pg_size_pretty(count(*) * 1024 * 8) buffer_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
--     AND c.relname = 'mytable'
GROUP BY c.relname
ORDER BY buffer_count DESC
LIMIT 3;
```

A: 1 bloc, because we used a pointer, ctid

| object\_name | buffer\_count | buffer\_size |
|:-------------|:--------------|:-------------|
| mytable      | 1             | 8192 bytes   |


The table `pg_buffercache` itself contains the block id and some counters, but we can't see the data
```postgresql
SELECT
    b.bufferid,
    b.*
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
--     AND c.relname = 'mytable'
```

Q: If we do not filter by a physical pointer, what happens ?
```postgresql
SELECT *
FROM mytable
WHERE 1=1
  AND id = 1
```

A: We can't know where the rows are, so we have to load all rows.
The whole table is in the cache.
```postgresql
SELECT
    c.relname object_name,
    count(*) AS buffer_count,
    pg_size_pretty(count(*) * 1024 * 8) buffer_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
--     AND c.relname = 'mytable'
GROUP BY c.relname
ORDER BY buffer_count DESC
LIMIT 3;
```
| object\_name | buffer\_count | buffer\_size |
|:-------------|:--------------|:-------------|
| mytable      | 443           | 3544 kB      |


```postgresql
SELECT
    b.bufferid,
    b.*
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
--     AND c.relname = 'mytable'
```

## Reading a big table - buffer ring

Q: What happens if you create a table bigger than cache ? 
```postgresql
select pg_size_pretty(setting::integer * 8 * 1024::numeric) cache_size
from pg_settings where name = 'shared_buffers'
```

```sql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
```

Table size is 346 Mb
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size;
```

Let's empty the cache
```shell
just restart-instance
```

And query 
```postgresql
SELECT *
FROM mytable
WHERE 1=1
  AND id = 1
```

And check 
```postgresql
SELECT
    c.relname object_name,
    count(*) AS buffer_count,
    pg_size_pretty(count(*) * 1024 * 8) buffer_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
--     AND c.relname = 'mytable'
GROUP BY c.relname
ORDER BY buffer_count DESC
LIMIT 3;
```

Only 32 buffers have been loaded !

| object\_name | buffer\_count | buffer\_size |
|:-------------|:--------------|:-------------|
| mytable      | 32            | 256 kB       |


All sequential scan of tables whose size exceed 25% of the cache use a smallish part of the cache, 32 buffers, called a buffer ring. When the ring is full, row are filtered - if they match, copied in the private memory of the process who runs the query; then read continue from OS cache, overwriting the buffer ring, and the cycle goes on. 

> Bulk reads strategy is used for sequential scans of large tables if their size exceeds of the buffer cache. The ring buffer takes 256 kn (32 standard pages).

Reference: PostgreSQL Internals, Part II - Buffer cache and WAL - Bulk eviction

## Reading many tables

If there is no space left in PostgreSQL cache, which happens all the time, some blocks should be evicted from the cache. In order to keep the one that are used most often, a usage counter is considered: the block that are evicted first are the less used.


Let's create two tables
```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 100000) AS n;

DROP TABLE IF EXISTS yourtable;

CREATE TABLE yourtable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO yourtable (id)
SELECT n
FROM generate_series(1, 100000) AS n;
```

The cache is empty at startup, let's restart the instance.
```shell
just restart-instance
```

Let's query to fill the cache
```postgresql
SELECT *
FROM mytable
WHERE 1=1
  AND id = 1
```

What's the use ?
```postgresql
SELECT
    b.usagecount,
    COUNT(*)
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
      AND c.relname = 'mytable'
GROUP BY 
    b.usagecount
```

All buffer has the same usage

| usagecount | count |
|:-----------|:------|
| 1          | 443   |

Let's query the same block again and again
```postgresql
SELECT *
FROM mytable
WHERE 1=1
    AND ctid = '(0,1)'
```

```postgresql
SELECT
    b.usagecount,
    COUNT(*)
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
      AND c.relname = 'mytable'
GROUP BY 
    b.usagecount
```

This block stands out, it will be evicted later than the others

| usagecount | count |
|:-----------|:------|
| 1          | 442   |
| 5          | 1     |


Let's query to fill the cache
```postgresql
SELECT *
FROM yourtable
WHERE 1=1
  AND id = 1
```

```postgresql
SELECT
    c.relname,
    b.usagecount,
    COUNT(*)
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'
GROUP BY 
    c.relname, b.usagecount
```

As you can see, both tables can fit the cache, so no eviction took place.
As no table which is bigger than 25% of the cache can be loaded completely, it is not easy to fill the cache by yourself in a test environment.

| relname   | usagecount | count |
|:----------|:-----------|:------|
| mytable   | 1          | 442   |
| mytable   | 5          | 1     |
| yourtable | 1          | 443   |


## Modifying data 

What happens if we modify a row, that is, we create a new version ?

```postgresql
SELECT ctid FROM mytable 
WHERE id=1
```
(0,1)
This is block 0

We update and get the block
```postgresql
UPDATE mytable 
SET id=-1
WHERE id=1
RETURNING ctid
```
(88495,131)

This is block 88495, tuple 131

The whole block is flagged as `dirty`
```postgresql
SELECT
    b.bufferid       cache_block_id,
    b.relblocknumber fs_block_id,
    b.isdirty,
    b.usagecount
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
    AND c.relname = 'mytable'
    AND b.relblocknumber = 88495
    --AND b.relblocknumber = 1
    AND b.isdirty IS TRUE
```

This is the only one.
```postgresql
SELECT
    c.relname,
    COUNT(*) dirty_blocks,
    pg_size_pretty(COUNT(*) * 8 * 1024) dirty_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
    --AND c.relname = 'mytable'    
    AND b.isdirty IS TRUE
GROUP BY 
    c.relname
```

We must make sure this block find its way to disk, sooner or later, or we may lose data.

## Writing to disk : checkpointer

### Manually

We can force writing the block to disk.
```postgresql
CHECKPOINT; 
```

It disappears, written to disk.
```postgresql
SELECT
    c.relname,
    COUNT(*) dirty_blocks,
    pg_size_pretty(COUNT(*) * 8 * 1024) dirty_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
    --AND c.relname = 'mytable'    
    AND b.isdirty IS TRUE
GROUP BY 
    c.relname
```

### Automatically

#### Periodically
This should be done automatically.

It is done by a background job, called background writer.
```shell
just shell
ps -fU postgres
```

It is pid `148716`
```
postgres       1       0  0 09:30 ?        00:00:13 postgres -c config_file=/etc/postgresql/postgresql.conf
postgres  148711       1  0 14:57 ?        00:00:00 postgres: io worker 0
postgres  148712       1  0 14:57 ?        00:00:00 postgres: io worker 1
postgres  148713       1  0 14:57 ?        00:00:00 postgres: io worker 2
postgres  148715       1  0 14:57 ?        00:00:00 postgres: checkpointer 
postgres  148716       1  0 14:57 ?        00:00:00 postgres: background writer 
postgres  148731       1  0 14:57 ?        00:00:00 postgres: walwriter 
postgres  148732       1  0 14:57 ?        00:00:00 postgres: autovacuum launcher 
postgres  148733       1  0 14:57 ?        00:00:00 postgres: logical replication launcher 
postgres  150486       1  0 15:01 ?        00:00:00 postgres: user database 172.18.0.1(52530) idle
```

It is launched, and is configurable, in two ways:
- periodically;
- punctually, if much data update activity is going on in the system.


You can get its statistics.
```postgresql
SELECT 
    'checkpoint=>'
    ,cp.num_requested   manual_count
    ,cp.num_timed       automatic_count
    ,cp.buffers_written block_count
    ,pg_size_pretty(cp.buffers_written * 8 * 1024) size
    ,'pg_stat_checkpointer=>'
    ,cp.*
FROM
    pg_stat_checkpointer cp
```

[Source](https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-CHECKPOINTER-VIEW)

You can reset them.
```postgresql
SELECT pg_stat_reset_shared('checkpointer')
```

#### If much activity

The checkpointer is disabled in this database for educative purpose, see [postgresql.conf](../../../../sandbox/configuration/postgresql.conf), section `Checkpointer`.

Still, we can trigger a checkpoint manually. 
```postgresql
CHECKPOINT; 
```

Check logs
```text
LOG: checkpoint starting: immediate force wait
```

If there is much update activity, the checkpointer will be triggered.

Such activity is related to WAL: if all WAL files size exceeds `max_wal_size`, a checkpoint is executed.

Let's do this.

```postgresql
CHECKPOINT 
```

Reset stats
```postgresql
SELECT pg_stat_reset_shared('checkpointer')
```

```postgresql
SELECT 
    'checkpoint=>'
    ,cp.num_requested   manual_count
    ,cp.num_timed       automatic_count
    ,cp.buffers_written block_count
    ,pg_size_pretty(cp.buffers_written * 8 * 1024) size
FROM
    pg_stat_checkpointer cp
```

| ?column?       | manual\_count | automatic\_count | block\_count | size    |
|:---------------|:--------------|:-----------------|:-------------|:--------|
| checkpoint=>   | 0             | 0                | 0            | 0 bytes |


Then insert more than 4 GB (1 minute)
```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 50_000_000) AS n;
```

Check log
```shell
docker logs postgresql 2>&1 | grep checkpoint
```

You got `checkpoint starting: wal`
```postgresql
2026-01-29 15:51:15.259 GMT [148715] LOG:  checkpoint starting: wal
```

The table 
```postgresql
SELECT    pg_size_pretty(pg_table_size('mytable'))  table_size
```
1729 MB


Check WAL size
```shell
just storage
/var/lib/postgresql/18/docker/pg_wal
4.0G	/var/lib/postgresql/data/pg_wal
```

Check stats
```postgresql
SELECT 
    'checkpoint=>'
    ,cp.num_requested   manual_count
    ,cp.num_timed       automatic_count
    ,cp.buffers_written block_count
    ,pg_size_pretty(cp.buffers_written * 8 * 1024) size
FROM
    pg_stat_checkpointer cp
```
| ?column?        | manual\_count | automatic\_count | block\_count | size  |
|:----------------|:--------------|:-----------------|:-------------|:------|
| checkpoint=&gt; | 1             | 0                | 11           | 88 kB |


## Writing to disk in the background : Background writer

The background writer does the same job as teh checkpointer, but in much smaller batches.

It is also disabled in this database for educative purpose, see [postgresql.conf](../../../../sandbox/configuration/postgresql.conf), section `Background writer`.
```postgresql
-- Execution frequency
SHOW bgwriter_delay; 

-- How many block to write in one pass, at most
SHOW bgwriter_lru_maxpages; 
```

It has its own statistics
```postgresql
SELECT 
     bgw.buffers_clean   blocks_written
    ,pg_size_pretty(bgw.buffers_clean * 8 * 1024)   size_written
    ,bgw.buffers_alloc cache_size_blocks
    ,pg_size_pretty(bgw.buffers_alloc * 8 * 1024)   cache_size
    ,bgw.maxwritten_clean too_many_buffers_written_count
    ,bgw.*
FROM pg_stat_bgwriter bgw
```
[Source](https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-BGWRITER-VIEW)

Reset
```postgresql
SELECT pg_stat_reset_shared('bgwriter')
```

## Writing to disk in emergency : Backend client

If the background writer and the checkpointer cannot handle the situation, we still didn't want to block queries.
If a query need a block, which is not in the cache, a cache block should be evicted.
If all blocks in the cache are dirty, we cannot evict them: we need to write some to disk.   

Let's provoke it
```postgresql
DROP TABLE IF EXISTS mytable ;
DROP TABLE IF EXISTS mytable1 ;
DROP TABLE IF EXISTS mytable2 ;

CREATE TABLE mytable1 (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
  
CREATE TABLE mytable2 (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable2 (id)
SELECT n
FROM generate_series(1, 1_000_000) AS n;

CHECKPOINT;
```

Evict
```postgresql
SELECT
    pg_buffercache_evict(b.bufferid)
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d  ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
--    AND c.relname NOT LIKE 'pg_%'
  AND c.relname = 'mytable2';
```

Check
```postgresql
SELECT
    c.relname,
    b.isdirty,
    COUNT(*) blocks,
    pg_size_pretty(COUNT(*) * 8 * 1024) dirty_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'    
    --AND b.isdirty IS TRUE
GROUP BY 
    b.isdirty, 
    c.relname
```

Now fill up the cache with dirty buffers
```postgresql
INSERT INTO mytable1 (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

Check
```postgresql
SELECT
    c.relname,
    b.isdirty,
    COUNT(*) blocks,
    pg_size_pretty(COUNT(*) * 8 * 1024) size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'    
    --AND b.isdirty IS TRUE
GROUP BY 
    b.isdirty, 
    c.relname
```
| relname  | isdirty | blocks | size   |
|:---------|:--------|:-------|:-------|
| mytable1 | false   | 5      | 40 kB  |
| mytable1 | true    | 15922  | 124 MB |

124 MB dirty buffers on mytable1


Reset stats
```postgresql
SELECT pg_stat_reset_shared('io')
```

And now read another table
```postgresql
SELECT SUM(id) FROM mytable2
```

Check
```postgresql
SELECT
    c.relname,
    b.isdirty,
    COUNT(*) blocks,
    pg_size_pretty(COUNT(*) * 8 * 1024) dirty_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
      AND c.relname NOT LIKE 'pg_%'    
    --AND b.isdirty IS TRUE
GROUP BY 
    b.isdirty, 
    c.relname
```

| relname  | isdirty | blocks | dirty\_size |
|:---------|:--------|:-------|:------------|
| mytable1 | false   | 5      | 40 kB       |
| mytable1 | true    | 12606  | 98 MB       |
| mytable2 | true    | 3353   | 26 MB       |

124 MB to 98 Mb dirty buffers on mytable1: 26 Mb data has been written
```postgresql
SELECT 124 - 98
```

Then query
```postgresql
SELECT 'I/O=>' _
     , io.backend_type
     , io.object
     , io.context
     , 'w=>OS' _ -- write PG cache => OS cache
     , io.writes         blocks
     , pg_size_pretty(io.write_bytes)  size
     , io.write_time     elapsed
FROM pg_stat_io io
WHERE 1 = 1
  AND (io.reads > 0 OR io.writes > 0)
  AND io.backend_type = 'client backend'
ORDER BY io.writes DESC
```

| \_       | backend\_type  | object   | context  | \_       | blocks | size   | elapsed |
|:---------|:---------------|:---------|:---------|:---------|:-------|:-------|:--------|
| I/O=&gt; | client backend | relation | bulkread | w=&gt;OS | 4423   | 35 MB  | 10.725  |
| I/O=&gt; | client backend | relation | normal   | w=&gt;OS | 11     | 88 kB  | 0.1     |
| I/O=&gt; | client backend | wal      | normal   | w=&gt;OS | 1      | 160 kB | 0.084   |


35 Mb have been written by the backend.