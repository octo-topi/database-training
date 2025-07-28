# Execution plan

## configuration 

PaaS
- hardware
- usage

## heap

heap = large random-access files

## Sandbox

Start instance
```shell
just start-instance
```

Check cache size is actually 125 Mb
```postgresql
select pg_size_pretty(setting::integer * 8 * 1024::numeric)
from pg_settings where name = 'shared_buffers'
```

## Insert a single row and explain


Create table
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (autovacuum_enabled = off)
```

Add data
```postgresql
INSERT INTO mytable (id) VALUES (-1);
```

Query table
```postgresql
SELECT id 
FROM mytable
```

Get execution plan (expected)
```postgresql
EXPLAIN
SELECT id 
FROM mytable
```

We get
```text
Seq Scan on mytable  (cost=0.00..35.50 rows=2550 width=4)
```

There is
```text
$operation on $object (cost=$..$ rows=$ width)
```
`Seq scan` stands for sequential scan

After actual:
- time elapsed first ... last
- row count

Cost is arbitrary

Why do we have 2 550 rows expected ?

We can get actual rows and timings by executing query with `ANALYZE` option 
Get execution plan (actual)
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
```

We get
```text
Seq Scan on mytable  (cost=0.00..35.50 rows=2550 width=4) (actual time=0.013..0.014 rows=1 loops=1)
Planning Time: 0.040 ms
Execution Time: 0.028 ms
```

After actual: 
- time elapsed first ... last
- row count

We have 1 row actual

## Update query-planner statistics

Update query-planner statistics
```postgresql
ANALYZE VERBOSE mytable;
```

Query table again
```postgresql
EXPLAIN (ANALYZE)
SELECT id 
FROM mytable
```

We now have 1 row expected = 1 row actual
```text
Seq Scan on mytable  (cost=0.00..1.01 rows=1 width=4) (actual time=0.009..0.010 rows=1 loops=1)
  Buffers: shared hit=1
Planning:
  Buffers: shared hit=7
Planning Time: 0.111 ms
Execution Time: 0.023 ms
```

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

## Get size and monitoring statistics

Statistics not used by query planner

Table size on disk
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))   data_size_pretty
```
1 block

Access statistics
```postgresql
SELECT
   stt.relname                       table_name,
   stt.n_live_tup                    row_count,
   'events=>',
   stt.n_tup_ins                     insert_count,
   stt.n_tup_upd + stt.n_tup_hot_upd update_count,
   stt.n_tup_del                     delete_count
   --,stt.*
FROM pg_stat_user_tables stt
WHERE 1=1
   AND relname = 'mytable'
;
```
| table_name | row_count | ?column? | insert_count | update_count | delete_count |
|:-----------|:----------|:---------|:-------------|:-------------|:-------------|
| mytable    | 1         | events=> | 1            | 0            | 0            |


Trigger events and check they appear

```postgresql
UPDATE mytable 
SET id = 1
WHERE id = -1;
```

```postgresql
DELETE FROM mytable
WHERE id = 1;
```

```postgresql
TRUNCATE TABLE mytable
```

## Data distribution 

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

## Insert many rows

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

