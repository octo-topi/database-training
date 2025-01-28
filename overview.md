# Overview

Guidelines:
- should include theory to bootstrap learning
- should include practice in order to test theory and highlight context effects 

## Basic : developers

### foundation

Several paradigm:
- key/value: redis
- relational: PostgreSQL
- graph: 
- document: ElasticSearch

### environment

Use Docker to start an instance :
- use healthcheck
- configure using `postgresql.conf`
- limit resource usage

Using a CLI :
- `psql` client, interactive and file mode
- [pgcli](https://www.pgcli.com/)

### using your database

SQL:
- Queries: SELECT, CTE, views
- DML: INSERT, UPDATE, DELETE
- DDL: CREATE TABLE, ALTER TABLE

Data model:
- logical model
- physical model

### development best practice

Schema versioning:
- key concepts
- Java: liquibase
- Js: knex

No-downtime deployment (ZDD):
- key concepts
- practice: rename a column in three deployments

Linting:
- naming standards
- constraints: primary key and foreign keys


## Medium : technical leaders and senior developers

### Foundations

#### MVCC

Store multiple versions :
- dead rows
- bloating

Practice:
- create a dataset an update rows
- display dead rows: pg_dirty
- recover space using VACUUM
- setting up AUTOVACUUM

Concurrency:
- isolation level
- locks 

Practice:
- create transactions
- get locks
- create a deadlock

#### Cache

Practice:
- querying the cache
- force eviction
- track ring buffer usage


### Observability

Server metrics:
- CPU
- RAM & swapping
- I/O : bandwidth, latency 

Database metrics:
- traffic
- table size and row count
- cache size, cache hit
- index usage

Identify running queries
- SQL text
- locks

Get completed queries
- single-query logging
- aggregated logging: `pg_stats_stements`

### Debugging

Get execution plan

Read an execution plan:
- basic : estimation
- medium : actual (IO timings)
- [use web interface](https://explain.dalibo.com) 

### Access path

Key concepts:
- selectivity (strong - weak) and cardinality
- index and partitions
- materialized views

#### Gathering statistics

How are statistics sampled ? 
- number
- text

Query histograms

When are statistics gathered ?

Practice : massive table loads
- practice: load dump
- use `FREEZE` option

#### Indexing

Type:
- b-tree
- bitmap

Drawbacks:
- redundancy (maintenance overhead)
- versioning side-effect (index rebuild)

Practice:
- design and create
- check usage

#### Partioning

Select partition key

Create a partition

Check access time VS fullscan

Sub-partitioning

### Advanced data types

Store and query text:
- fulltext search
- pg_trgm, fuzzystrmatch, LEVENSHTEIN

Store and query JSON

Store and query binary: BLOB, BYTEA

### Application integration

#### Pool

#### Native VS Query builder VS ORM

#### Transaction

How to abstract it in your domain ?

#### Automated tests

Integration tests: quick feedback VS protection against regression

Should you use an in-memory database ?

#### hexagonal/clean architecture drawbacks

#### deployment

Preventing deadlocks

Should you revert ? How to do it ?

#### APM and query correlation

DIY: monkey-patching 

On-the-shelf: openTelemetry (Js), Jaeger (Java)

## Advanced : auditors and performance advisor

Data layout
- heap segment
- free space map
- visibility map

ID wraparound and freeze operation

TOAST

cpu_cost, io_cost, index_cost

Trigger

stored procedure

PaaS or DBaaS

Wait events

Sizing client process memory: work_mem, temp files, OOM

Performance tests

Parallelization

Monitoring and optimizing data-related activity:
- pg_writer
- pg_wal_writer : fullpage write, fs full

Capture Data Change

Replication

## Appendix : resources

### online

[The internals of PostgreSQL website](https://www.interdb.jp/pg/)

[Dalibo training content](https://www.dalibo.com/en/formations)

[PostgreSQL internals book](https://postgrespro.com/community/books/internals)

[SQL performance explained book](https://use-the-index-luke.com/)

[SQL roadmap](https://roadmap.sh/sql)

[PostgreSQL roadmap](https://roadmap.sh/postgresql-dba)

### printed only

[PostgreSQL - Architecture et notions avancées](https://www.amazon.fr/PostgreSQL-Architecture-avanc%C3%A9es-Guillaume-Lelarge-ebook/dp/B083R1H7YH)

 

