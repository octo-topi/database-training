# More

## Optimistic execution time

`EXPLAIN ANALYZE` displays: 
- planning time, which does not include parsing and rewriting some steps; 
- an execution time an execution time, which does not include serialization (actually reading all data) and sending data to client.

You can get serialization time if needed.
```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

```postgresql
EXPLAIN (ANALYZE, SERIALIZE)
SELECT * FROM mytable
```

You get a `Serialization` section
```text
| QUERY PLAN |
| :--- |
| Seq Scan on mytable  \(cost=0.00..157080.40 rows=11283240 width=4\) \(actual time=0.419..681.592 rows=10000000.00 loops=1\) |
|   Buffers: shared hit=15894 read=28354 dirtied=28354 written=28354 |
|   I/O Timings: shared read=51.905 write=97.022 |
| Planning: |
|   Buffers: shared hit=9 read=9 written=9 |
|   I/O Timings: shared read=1.117 write=0.061 |
| Planning Time: 1.444 ms |
| Serialization: time=707.585 ms  output=125869kB  format=text |
| Execution Time: 1835.085 ms |
```

Serialization took one-third of execution time (707 ms of 1835 ms). 
```text
| Serialization: time=707.585 ms  output=125869kB  format=text |
| Execution Time: 1835.085 ms |
```

> The Planning time shown by EXPLAIN ANALYZE is the time it took to generate the query plan from the parsed query and optimize it. It does not include parsing or rewriting.

> The Execution time shown by EXPLAIN ANALYZE includes executor start-up and shut-down time, as well as the time to run any triggers that are fired, but it does not include parsing, rewriting, or planning time.

> There are two significant ways in which run times measured by EXPLAIN ANALYZE can deviate from normal execution of the same query. First, since no output rows are delivered to the client, network transmission costs are not included. I/O conversion costs are not included either unless SERIALIZE is specified. Second, the measurement overhead added by EXPLAIN ANALYZE can be significant.

[Reference](https://www.postgresql.org/docs/current/using-explain.html)

## Non-deterministic execution time

The same query, given the same visible data, can take more or less time to execute, see below.
Therefore, an execution plan is not enough to know what is going to happen.

Waiting to get a connexion (see Dalibo pg_bench connexion)

Waiting to acquire lock

CPU hoarding (other backend processes or internal : autovacuum, wal_writer, checkpointer)
I/O hoarding (wal_writer)

Cache 
- dirty
- miss

Table bloat, outdated visibility map, incorrect data statistics leading to suboptimal execution plans.


## Client execution modes

On a single connexion
- run a single query, get first results (LIMIT)
- run a single query, get some results (paginate)
- run a single query, get all results at once (less trips)
- run a single query, get results by chunks (less memory consumption)
- run multiple queries in parallel "pipeline" (less waits)

How to paginate
https://www.cybertec-postgresql.com/en/pagination-problem-total-result-count/


No fetch size in Java by default
https://shaneborden.com/2025/10/14/understanding-and-setting-postgresql-jdbc-fetch-size/

Pipeline - libpqonly
https://github.com/knex/knex/issues/5632
www.postgresql.org/docs/current/libpq-pipeline-mode.html

Chunk mode
https://www.postgresql.org/docs/current/libpq-single-row-mode.html