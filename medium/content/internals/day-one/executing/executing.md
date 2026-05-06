# Executing

## What is a backend process ?

We saw the features PostgreSQL use to persist data, make them quickly available, to update them - preventing data loss in crash.
We saw PostgreSQL's own processes: autovacuum, WAL writer, background writer, checkpointer.

But we don't look into the client-facing processus, also called backend processes.

I won't go into details, the most important is that :
- when a client connect to the database, an OS process is created to execute all the queries the client will send, it is called the "backend process":
- to read a table, the backend process will look into the cache by itself - if the block is missing, it will ask the OS for it and put into the cache;
- the process will then filter the rows, join table, aggregate data in its own private memory.

## Data handling

The cache, properly called "shared buffers", is the only data that is shared between processes. It is the data source for the queries, all operations are done by the backend process itself. That means if you filter a 4 GB table into a 2 GB intermediary result, these 2GB should go through the backend process memory in some way. They cannot be stored in the cache. 

When possible, the operation is pipelined to minimize the footprint; data is extracted from the cache as late as possible.
However, some operations process a whole dataset, e.g. aggregations or some sort. 
When this happens, if the memory needed exceeds `work_mem` [(4MB by default)](https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-WORK-MEM), PostgreSQL use its own swap mechanism by doing the operation using flat file, called temp files.

This is why configuring a PostgreSQL instance should be done considering its usage, e.g. :
- many queries returning very few non-aggregated data for a web application;
- a handful of queries processing huge dataset for a data warehouse.

## Process private memory

Let's see this in action.

We need query that will generate a lot of computed, unpipelined data.
How much data do we need ?

We need more than 1MB
```postgresql
SHOW work_mem 
```
615 kb

1 million integers are 4MB, much more than our `work_mem` 
```postgresql
SELECT pg_size_pretty(1_000_000 * 4::BIGINT)
```
4 MB

Let's create a table with 1 million integer rows.
```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (autovacuum_enabled = FALSE);

TRUNCATE mytable;

INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;
```

We use `ORDER BY` in combination with `SUM` to prevent pipelined execution. 
```postgresql
SELECT MAX(id)
FROM (SELECT id FROM mytable ORDER BY id DESC);
```

Check the logs to see what happened.
```shell
docker logs postgresql 2>&1 | grep temp
```

You see a temp file has been generated.
```text
2026-02-03 14:31:19.382 GMT [154864] LOG:  temporary file: path "base/pgsql_tmp/pgsql_tmp154864.1", size 12066816
```

You can use `ANALYZE` to get the figures the query
```postgresql
EXPLAIN ANALYZE
SELECT MAX(id)
FROM (SELECT id FROM mytable ORDER BY id DESC);
```

We output is rather long.
```text
Aggregate  (cost=143110.89..143110.90 rows=1 width=4) (actual time=257.192..257.195 rows=1.00 loops=1)
"  Buffers: shared hit=4425, temp read=4414 written=4452"
  I/O Timings: temp read=7.022 write=8.622
  ->  Sort  (cost=138110.89..140610.89 rows=1000000 width=4) (actual time=153.684..198.015 rows=1000000.00 loops=1)
        Sort Key: mytable.id DESC
        Sort Method: external merge  Disk: 11784kB
"        Buffers: shared hit=4425, temp read=4414 written=4452"
        I/O Timings: temp read=7.022 write=8.622
        ->  Seq Scan on mytable  (cost=0.00..14425.00 rows=1000000 width=4) (actual time=0.016..31.566 rows=1000000.00 loops=1)
              Buffers: shared hit=4425
Planning:
  Buffers: shared hit=4
Planning Time: 0.141 ms
Execution Time: 259.720 ms
```

Now, we can spot the `Sort` node
```text
  ->  Sort  (cost=138110.89..140610.89 rows=1000000 width=4) (actual time=153.684..198.015 rows=1000000.00 loops=1)
        Sort Key: mytable.id DESC
        Sort Method: external merge  Disk: 11784kB
```
It used 11 784 kB of temp file to sort. 

Now, if we give it plenty of memory. 
```postgresql
SET work_mem TO '100MB'
```

Run the query again.
```postgresql
SELECT MAX(id)
FROM (SELECT id FROM mytable ORDER BY id DESC)
```

There is no more temp logs.
```shell
docker logs postgresql 2>&1 | grep temp
```

Let's see in detail.
```postgresql
EXPLAIN ANALYZE
SELECT MAX(id)
FROM (SELECT id FROM mytable ORDER BY id DESC);
```

```text
Aggregate  (cost=119082.84..119082.85 rows=1 width=4) (actual time=118.901..118.904 rows=1.00 loops=1)
  Buffers: shared hit=4425
  ->  Sort  (cost=114082.84..116582.84 rows=1000000 width=4) (actual time=66.785..90.160 rows=1000000.00 loops=1)
        Sort Key: mytable.id DESC
        Sort Method: quicksort  Memory: 24577kB
        Buffers: shared hit=4425
        ->  Seq Scan on mytable  (cost=0.00..14425.00 rows=1000000 width=4) (actual time=0.020..32.107 rows=1000000.00 loops=1)
              Buffers: shared hit=4425
Planning Time: 0.065 ms
Execution Time: 118.948 ms
```

The sort node used 24 MB of memory
```text
  ->  Sort  (cost=114082.84..116582.84 rows=1000000 width=4) (actual time=66.785..90.160 rows=1000000.00 loops=1)
        Sort Method: quicksort  Memory: 24577kB
```

Let's restore this setting
```postgresql
RESET work_mem 
```

## Query workflow

Slides

## Monitor execution time

Many ways, starting from the most basic.

### In database side

On a single query, use EXPLAIN with ANALYZE.

On a single query, use `psql` client : 
  - get execution time using [timing parameter](https://www.postgresql.org/docs/current/app-psql.html#APP-PSQL-META-COMMAND-TIMING) or use OS timing;
  - you must fetch the results;
  - you must execute the query several times.

On all queries, add execution time or execution plan in logs.

[Tutorial](https://github.com/GradedJestRisk/batch-queries-postgresql/blob/main/basic-container-management/directives.md)

### In the backend

Use your backend application and activate `pg_stat_statements`.

Add monitoring in your backend application.

[Tutorial](https://github.com/GradedJestRisk/batch-queries-postgresql/blob/main/monitor-execution-time/directives.md)

### End-to-end

Use an APM on production