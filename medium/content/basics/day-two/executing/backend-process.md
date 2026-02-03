# Backend process

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
SELECT SUM(id)
FROM (SELECT id FROM mytable ORDER BY id DESC)
```

Check the logs to see what happened.
```shell
docker logs postgresql 2>&1 | grep temp
```

You see a temp file has been generated.
```text
2026-02-03 14:31:19.382 GMT [154864] LOG:  temporary file: path "base/pgsql_tmp/pgsql_tmp154864.1", size 12066816
```

Now, if we give it plenty of memory. 
```postgresql
SET work_mem TO '100MB'
```

Run the query again.
```postgresql
SELECT SUM(id)
FROM (SELECT id FROM mytable ORDER BY id DESC)
```

There is no more logs.
```shell
docker logs postgresql 2>&1 | grep temp
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
  - you must execute teh query several times.

On all queries, add execution time in logs.

[Tutorial](https://github.com/GradedJestRisk/batch-queries-postgresql/blob/main/basic-container-management/directives.md)

### In the backend

Use your backend application and activate `pg_stat_statements`.

Add monitoring in your backend application.

[Tutorial](https://github.com/GradedJestRisk/batch-queries-postgresql/blob/main/monitor-execution-time/directives.md)

### End-to-end

Use an APM on production