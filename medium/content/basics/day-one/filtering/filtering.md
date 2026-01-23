


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
$operation on $object  (cost=$setup..$total    rows=$row_count    width=$average_size_row_bytes)
Seq Scan   on mytable  (cost=0.00..35.50       rows=2550          width=4)
```

[doc](https://www.postgresql.org/docs/current/using-explain.html)

So:
- operation : `Seq scan`, stands for sequential scan
- object    : `mytable` table; it can also be an index, a partition
- cost      : `0` for the setup, then `35` for retrieving all rows 
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

TODO: do we have many lines or none ?
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

