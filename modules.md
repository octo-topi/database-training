# Overview

Guidelines:
- should include theory to bootstrap learning
- should include practice in order to test theory and highlight context effects 

## Basic : developers

### scope

Duration: 3 days
Creation: 6 days

### Pre-requisite

Know the relational model
- what is a table, a primary key, a foreign key 
- write and execute basic SQL queries, at least a SELECT with JOIN and a WHERE clause

### foundation

Choose the database you need.

Several paradigm:
- key/value: redis
- relational: PostgreSQL
- graph: 
- document: ElasticSearch
- hybrid

### local environment

Being able to start a database server  locally and run queries against it using a client.

Use Docker and compose to start a PostgreSQL server :
- configure exposed port, credentials and database name ;
- use healthcheck to make sure it's properly started ;
- know you data won't be persisted between container restart ;
- know the memory usage is limited to a small extent by default by PostgreSQL itself ;
- know the CPU and I/O usage is not limited by default ;
- know you can change resource usage using [pgtune](https://pgtune.leopard.in.ua/) and `postgresql.conf`.

Using a CLI :
- `psql` client
   - interactive mode, to get schema description and run SQL queries
   - file mode, to run scripts
- [pgcli](https://www.pgcli.com/)

### using your database

SQL:
- Queries: SELECT, CTE, views
- DML: INSERT, UPDATE, DELETE, TRUNCATE
- DDL: CREATE TABLE, ALTER TABLE

Data model:
- logical model : primary key, foreign keys, constraints (unique not null, function)
- physical model : partition

Business data type:
- facts
- dimension
- configuration

Should you 
- expose primary keys to other applications ?
- use technical id, application-generated (uuid) or functional (composite) ?

### import data

CSV using `COPY FROM`

### libraries

Basics of:
- client with/without connexion pool
- transactions
- query-builder
- ORM

### development best practice

Schema versioning:
- key concepts
- Java: liquibase
- Js: knex

No-downtime deployment (ZDD):
- key concepts
- practice: rename a column in three deployments

Linting (optional):
- naming standards
- constraints: primary key and foreign keys

## Medium : technical leaders and senior developers

### Scope and cost

Creation: 9 days, spent 4.5

Duration: 6 days

Parts
- [one : basics - 3 days ](medium/content/basics):
  - heap : pro/cons, storage layout (blocks)
  - monitor a query : execution plan, statistics
  - index : pro/cons, storage layout, optimization
  - tuning : 
- [two : performance tests - 2 days](medium/content/performance-tests) 
- [three : application integration - 1 day](medium/content/application-integration)

Day 1 : execution plan + heap, cache, MVCC

By the end of the day, you should know about
- heap : large random-access files
  - locate the file
  - how it grows when inserting, modifying, deleting data
- cache : speed up queries
  - track its impact : execution plan, execution time 
  - explore its content
  - clear the cache
  - force-load the cache
- MVCC and its impact on performance
  - dead_rows, bloat 
  - optimization : visibility map
- statistics 
  - row count
  - data distribution
- reading an execution plan
  - nodes
  - access path
  - volume, estimated and actual
  - cost, unit and total
- data modification : impact on performance
- partitions : another access path

Day 2 : indexes
- why using indexes ? index theory
- access paths (index or heap) and filtering

- choose a path: costs (based on access type + estimated rows)
- reading an execution plan (chosen path) and check if appropriate
- practice: creating indexes and using them on `SELECT`
  - different data distribution
  - modifying data and updating statistics
  - use only execution plan to estimate execution time

Day 3 : performance 
- benchmarking using `pg_stat_statements`
- scaling : counter-intuitive phenomenons
  - latency of indirections in production
  - more capacity, not faster
- data modification : index update cost (1 index)


### Pre-requisite

[Basic](#basic--developers) 

How to make sure everybody knows the basics:
 - ask questions informally
 - submit MCQ
 - browse a codebase and ask for bugs

### Content

#### Foundations

##### MVCC

Store multiple versions :
- dead rows
- bloating

Practice:
- create a dataset and update rows
- display dead rows: pg_dirty + views
- recover space using VACUUM
- setting up AUTOVACUUM

Concurrency:
- isolation level
- transaction
- locks ( include advisory lock on virtual resource ?) 

Practice:
- create transactions
- get locks (lock-tree)
- create a deadlock

##### Cache

Practice:
- querying the cache
- force eviction
- track ring buffer usage


##### WAL

#### Observability

Server metrics:
- CPU
- RAM & swapping
- I/O : bandwidth, latency 

Database metrics and statistics :
- traffic
- table size and row count
- cache size, cache hit
- index usage

Identify running queries
- SQL text
- locks
- wait events

Get completed queries
- single-query logging (log in fs)
- aggregated logging: `pg_stats_stements`

#### Debugging

Get execution plan

Read an execution plan:
- basic : estimation
- medium : actual (IO timings)
- [use web interface](https://explain.dalibo.com) 

#### Access path

Key concepts:
- selectivity (strong - weak) and cardinality
- index 
- partitions

Practice:
- create index
- get use case when not used
- get use case when used

##### Gathering statistics

How are statistics sampled ? 
- number
- text

Query histograms views

When are statistics gathered ?

##### Import data

Practice : massive table loads
- load data
  - using streams : `COPY TO stdout | COPY FROM stdin`
  - using flat-file : `COPY TO` + `COPY FROM`
  - using plain SQL : `pg_dump` and `psql`
  - using custom format (archive) : `pg_dump` and `pg_restore`
- use `FREEZE` option
- disable constraints and indexes
- use `ANALYZE`

##### Remote data source
Foreign Data Wrapper


##### Indexing

Type:
- b-tree
- bitmap

Type:
- single column
- composite
- function-based

Covering index

Drawbacks:
- redundancy (maintenance overhead)
- versioning side-effect (index rebuild)

Practice:
- design and create (simple, composite)
- check usage

##### Partioning

Select partition key

Create a partition

Check access time VS full-scan

Sub-partitioning

#### Advanced data types

##### Text
Store and query text:
- fulltext search
- `pg_trgm`, `fuzzystrmatch`, Levenshtein

##### JSON
Store and query JSON

##### Binary 
Store and query binary: BLOB, BYTEA

##### Vector
`pg_vector`


#### Application integration

##### Pool

max_connection

PaaS and autoscaling

##### Native VS Query builder VS ORM

##### Transaction

How to abstract it in your domain ?

##### Automated tests

Integration tests: quick feedback VS protection against regression

Should you use an in-memory database : 
- when usage is in the soft spot;
- when to go out.


##### Application design (interaction with database) 

###### Primary key

UUID 

[v4 is bad for performance](https://www.cybertec-postgresql.com/en/unexpected-downsides-of-uuid-keys-in-postgresql/)

###### Hexagonal / clean architecture

When to do, when not to do

###### DDD

An aggregate :
- in a single table;
- in a dedicated schema.

Can you keep referential integrity between bounded context ?

##### deployment

ZDD (blue/green)
Preventing deadlocks 
Should you revert ? How to do it ?

##### APM and query correlation

DIY: monkey-patching 

On-the-shelf: openTelemetry (Js), Jaeger (Java)

## Advanced : auditors and performance advisor

### Pre-requisite

### Scope

### Data layout

Concepts
- heap segment
- free space map
- visibility map

ID wraparound and freeze operation

TOAST

### sizing 

#### hardware

cpu_cost, io_cost, index_cost

#### instance

shared_mem

#### client process memory

work_mem, temp files, OOM

### Extensions

Trigger

materialized views

stored procedure

### PaaS or DBaaS

### More on wait events

### Performance tests

### Parallelization

### Monitoring and optimizing 

pg_bench, pb_backrest 

Data-related activity:
- pg_writer
- pg_wal_writer : full page write, fs full

### Capture Data Change

### Replication

Incremental backup/restore

Patroni

## Appendix : resources

### online

[The internals of PostgreSQL website](https://www.interdb.jp/pg/)

[Dalibo training content](https://www.dalibo.com/en/formations)

[PostgreSQL internals book](https://postgrespro.com/community/books/internals)

[SQL performance explained book](https://use-the-index-luke.com/)

[SQL roadmap](https://roadmap.sh/sql)

[PostgreSQL roadmap](https://roadmap.sh/postgresql-dba)

[Use the index, Luke !](https://use-the-index-luke.com/sql/preface)

[7 things a developer should know](https://blog.octo.com/7-things-a-developer-should-know-about-databases)

### printed only

[PostgreSQL - Architecture et notions avancées](https://www.amazon.fr/PostgreSQL-Architecture-avanc%C3%A9es-Guillaume-Lelarge-ebook/dp/B083R1H7YH)

