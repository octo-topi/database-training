# Final tests

## Experiment

How can you find out if your SELECT query response time is influenced by :
- bloat due to MVCC;
- caching;
- WAL ?

Design an experiment to find out: you've gone one hour.

## Tooling

To measure response time, you can use one of the following:
- OS `time` function over `psql` client;
- `TIMING` in `psql` client;
- database logging facility;
- `pg_stat_statements` extension;
- `auto-explain` extension;
- `pgbench`.

All these methods are documented here:
- [time, TIMING, db logging](https://github.com/GradedJestRisk/batch-queries-postgresql/blob/main/basic-container-management/implementation/implementation.md#monitor-execution-time)
- [pg_stat_statements, auto-explain, pgbench](https://github.com/GradedJestRisk/batch-queries-postgresql/blob/main/monitor-execution-time/implementation/implementation.md)

Hint: for WAL concern, see [UNLOGGED table](resilience/more.md)

Pick the one you can use now.

## Wait time

Keep in mind the execution time include waiting time.

There is tow kind of waiting time:
- I/O from disk;
- lock acquire time.

You can execute this query in watch mode in `psql` to see waits.
```postgresql
SELECT
    pid,
    SUBSTRING(query,1, 50),
    ssn.state,
    ssn.wait_event_type,
    query_start started_at,
    now() - query_start started_since
FROM pg_stat_activity ssn
WHERE 1=1  
  AND ssn.backend_type = 'client backend'
  AND ssn.pid <>  pg_backend_pid()
;
\watch 0,5
```