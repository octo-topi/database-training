# Process

## Data handling

We saw till the features PostgreSQL use to persist data, make them quickly available, to update them - preventing data loss in crash.
We saw PostgreSQL's own processes: autovacuum, WAL writer, background writer, checkpointer.
But we don't look into the client-facing processus, also called backend processes.

I won't go into details, the most important is that :
- when a client connect to the database, an OS process is created to execute all the queries the client will send, it is called the "backend process":
- to read a table, the backend process will look into the cache by itself - if the block is missing, it will ask the OS for it and put into the cache;
- the process will then filter the rows, join table, aggregate data in its own private memory.

The cache, properly called "shared buffers", is the only data that is shared between processes. It is the data source for the queries, all operations are done by the backend process itself. That means if you filter a 4 GB table into a 2 GB intermediary result, these 2GB should go through the backend process memory in some way. They cannot be stored in the cache. 

When possible, the operation is pipelined to minimize the footprint; data is extracted from the cache as late as possible.
However, some operations process a whole dataset, e.g. aggregations or some sort. 
When this happens, if the memory needed exceeds `work_mem` [(4MB by default)](https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-WORK-MEM), PostgreSQL use its own swap mechanism by doing the operation using flat file, called temp files.

This is why configuring a PostgreSQL instance should be done considering its usage, e.g. :
- many queries returning very few non-aggregated data for a web application;
- a handful of queries processing huge dataset for a data warehouse.

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