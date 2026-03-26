# Access paths

As more and more data made their way into your system, you should think about scalability.

Sequential scan complexity is O(n).

How can we keep execution time constant :
- depending on only of the size of the result set;
- independently of the underlying data size ?

## Read data more quickly

### Parallel sequential scan

Use several CPU and devices if any.

You need to change instance configurations :
- several CPU in [.envrc](../../../../sandbox/.envrc);
- set `max_parallel_workers*` settings in [postgresql.conf](../../../../sandbox/configuration/postgresql.conf). 

Eg, for 10 CPU using [pgtune](https://pgtune.leopard.in.ua/?dbVersion=17&osType=linux&dbType=web&cpuNum=10&totalMemory=500&totalMemoryUnit=MB&connectionNum=&hdType=ssd)
```text
max_parallel_workers_per_gather = 4
max_parallel_workers = 10
max_parallel_maintenance_workers = 4
```

Restart
```postgresql
SHOW max_parallel_workers
```

Create dataset
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id) VALUES (-1);
```

Then get execution plan
```postgresql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id 
FROM mytable
WHERE id = 1
```

It is not parallelized
```text
| QUERY PLAN |
| :--- |
| Seq Scan on mytable  \(cost=0.00..41.88 rows=13 width=4\) \(actual time=0.020..0.020 rows=0.00 loops=1\) |
|   Filter: \(id = 1\) |
|   Rows Removed by Filter: 1 |
|   Buffers: shared hit=1 |
| Planning: |
|   Buffers: shared hit=4 |
| Planning Time: 0.090 ms |
| Execution Time: 0.036 ms |
```

Insert data

```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;

ANALYZE mytable;
```

Then get execution plan
```postgresql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id 
FROM mytable
WHERE id = 1
```

It is parallelized
```text
| QUERY PLAN |
| :--- |
| Gather  \(cost=1000.00..76498.25 rows=1 width=4\) \(actual time=0.853..108.057 rows=1.00 loops=1\) |
|   Workers Planned: 4 |
|   Workers Launched: 4 |
|   Buffers: shared read=44248 |
|   I/O Timings: shared read=130.952 |
|   -&gt;  Parallel Seq Scan on mytable  \(cost=0.00..75498.15 rows=1 width=4\) \(actual time=81.395..102.486 rows=0.20 loops=5\) |
|         Filter: \(id = 1\) |
|         Rows Removed by Filter: 2000000 |
|         Buffers: shared read=44248 |
|         I/O Timings: shared read=130.952 |
| Planning: |
|   Buffers: shared hit=12 read=14 |
|   I/O Timings: shared read=0.807 |
| Planning Time: 1.063 ms |
| Execution Time: 108.113 ms |
```

### Read the same table for several queries

The feature is called "Synchronized Sequential Scans"

```postgresql
SHOW synchronize_seqscans
```

[Example](https://dev.to/franckpachot/postgresql-synchronized-sequential-scans-and-limit-without-an-order-by-1kia)

https://www.cybertec-postgresql.com/en/data-warehousing-making-use-of-synchronized-seq-scans/

### Asynchronous I/O

Version 18 and upward

```postgresql
SHOW io_method
```
worker

```postgresql
SELECT
    setting, enumvals
FROM pg_settings s
WHERE 1=1
    AND s.name = 'io_method'
;
```

[Source](https://www.postgresql.org/about/news/postgresql-18-released-3142/)


### Streamlined I/O

Version 17 ands upward

```postgresql
SHOW io_combine_limit
```
128kb

```postgresql
SELECT
    setting, s.unit, s.setting, 
    min_val, pg_size_pretty((8 * 1024 * min_val::INT)::BIGINT) min_bytes,
    max_val, pg_size_pretty((8 * 1024 * max_val::INT)::BIGINT) max_bytes
FROM pg_settings s
WHERE 1=1
    AND s.name = 'io_combine_limit'
;
```

[Source](https://pganalyze.com/blog/5mins-postgres-17-streaming-io)

## Read less data

### By design

You can read less data by storing less data in the table, by having fewer columns (normalization) of fewer rows (archiving).
However, if this has not been done by design at the very start, it can lead to massive application code change. 

### Partitions

By storing data in different file (segregation), we can avoid reading data we don't need.

This can be achieved :  
- applicatively (e.g. storing orders to deliver in one table, and delivered one in another table).
- natively in PostgreSQL using a partition.

Indexes on partitions are smaller, and can then fit into the cache.

The drawback of partitions is related to the partition key: 
- you can't change the partition key (unless re-creating the table);
- the access can be slower if you fetch records from more than one partition.

```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) PARTITION BY RANGE(id)
;

CREATE TABLE mytable_less_than_million PARTITION OF mytable FOR VALUES FROM (1) TO (1_000_000);
CREATE TABLE mytable_more_than_million PARTITION OF mytable FOR VALUES FROM (1_000_000) TO (MAXVALUE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;

ANALYZE mytable;
```

Let's check there is a file per partition.
```postgresql
SELECT 
    pg_size_pretty(pg_table_size('mytable')) root,
    pg_size_pretty(pg_table_size('mytable_less_than_million')) partition_one,
    pg_size_pretty(pg_table_size('mytable_more_than_million')) partition_two
```

Indeed, and the second one is ten times larger than the first one.

| root    | partition\_one | partition\_two |
|:--------|:---------------|:---------------|
| 0 bytes | 35 MB          | 311 MB         |


Let's query
```postgresql
EXPLAIN 
SELECT * FROM mytable WHERE id < 1_000_000
```

We see that `mytable_less_than_million` table is scanned.
```text
| QUERY PLAN |
| :--- |
| Seq Scan on mytable\_less\_than\_million mytable  \(cost=0.00..16924.99 rows=999899 width=4\) |
|   Filter: \(id &lt; 1000000\) |
```

Let's compare to a unpartitioned table.
```postgresql
SET ENABLE_PARTITION_PRUNING TO OFF;

EXPLAIN 
SELECT * FROM mytable WHERE id < 1_000_000
```

We have
```text
| QUERY PLAN |
| :--- |
| Append  \(cost=0.00..174251.57 rows=1000799 width=4\) |
|   -&gt;  Seq Scan on mytable\_less\_than\_million mytable\_1  \(cost=0.00..16924.99 rows=999899 width=4\) |
|         Filter: \(id &lt; 1000000\) |
|   -&gt;  Seq Scan on mytable\_more\_than\_million mytable\_2  \(cost=0.00..152322.59 rows=900 width=4\) |
|         Filter: \(id &lt; 1000000\) |
```

Let's delete them
```postgresql
DROP TABLE IF EXISTS mytable_less_than_million;
DROP TABLE IF EXISTS mytable_more_than_million;
DROP TABLE IF EXISTS mytable;
```

### Indexes

We'll cover them in detail later.