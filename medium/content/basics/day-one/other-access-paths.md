# Access paths

## Read data more quickly


### Parallel sequential scan

Use several CPU and devices if any.

You need to change instance configurations :
- several CPU in [.envrc](../../../sandbox/.envrc);
- set `max_parallel_workers*` settings in [postgresql.conf](../../../sandbox/configuration/postgresql.conf). 

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
FROM generate_series(1, 10000000) AS n;

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

### Partitions