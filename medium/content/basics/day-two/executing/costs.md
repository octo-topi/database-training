## Sequential scan

Q: What happens when reading a whole table ?

A : The following:
- read all table blocks from cache
- for each block:
  - access each row using tuple pointer
  - for each tuple, check if it visible
  - if yes, return it 


### Read buffers

As we cannot know if the block will be in the cache, PostgreSQL assume that it will have to read it from the disk.

The cost of this operation, named `seq_page_cost`, is assigned the arbitrary value 1.
It is taken as the reference for all other costs' parameter.
```postgresql
SHOW seq_page_cost 
```
1


```postgresql
SHOW random_page_cost 
```

### Get rows from buffers

We can know how any rows there are in each block ... if we read the block and check the item pointer.
We don't want to do that - we'll rely on the row count from the stats.

Applying an operator to a row has a cost named `cpu_tuple_cost` which is 1/100 of `seq_page_cost`.
```postgresql
SHOW cpu_tuple_cost
```
0.01

### Sum up

Let's create a table.
```postgresql
TRUNCATE mytable;

INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;

SELECT COUNT(*) FROM mytable;
SELECT * FROM mytable;
```


What is the estimated cost ? 
```postgresql
EXPLAIN 
SELECT * FROM mytable
```

```text
Seq Scan on mytable  (cost=0.00..14425.00 rows=1000000 width=4)
```

Cost is `14 425`


Let's compute it ourselves.
```postgresql
WITH read_block AS (
    SELECT 
        current_setting('seq_page_cost') one_block,
        c.relpages * current_setting('seq_page_cost')::DECIMAL whole_file
    FROM pg_class c
        JOIN pg_stats s ON s.tablename = c.relname
    WHERE c.relname = 'mytable'
        ), 
   decode_block AS (
    SELECT 
        current_setting('cpu_tuple_cost') one_row,
        c.reltuples * current_setting('cpu_tuple_cost')::DECIMAL whole_table
    FROM pg_class c
        JOIN pg_stats s ON s.tablename = c.relname
    WHERE c.relname = 'mytable'       
) 
SELECT 
    'read block=>',
    r.one_block, r.whole_file,
    'decode block=>',
    f.one_row, f.whole_table,
    'whole=>',
    r.whole_file + f.whole_table cost
FROM read_block r, decode_block f 
```

## Sequential scan with filter

Q: What happens when reading a whole table ?
A : The same as in sequential table scan, add then a filter is applied

Q: Where does this happens ? In which memory ?
A: Buffer from seq scan are stored in shared_buffers, filtered rows are stored in the backend process memory.

### Filter

As we saw in [filtering](../filtering), we can estimate how many rows we will get.
However, we want here the cost of the operation: all visible rows will have to be filtered. 

Applying an operator to a row has a cost named `cpu_operator_cost` which is 1/400 of `seq_page_cost`.
```postgresql
SHOW cpu_operator_cost
```
0.0025

### Sum up

Let's create a table.
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

TRUNCATE TABLE mytable;

INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 1_000_000) AS n;

INSERT INTO mytable (id)
SELECT 2
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;

SELECT * FROM mytable;
```

What is the cost for scan ?
```postgresql
EXPLAIN 
SELECT * FROM mytable
```
28 850

What is the cost for scan and filter ?
```postgresql
EXPLAIN 
SELECT * FROM mytable
WHERE id = 2
```
33 850

Let's compute it ourselves.
```postgresql
WITH 
    read_block AS (
    SELECT 
        current_setting('seq_page_cost') one_block,
        c.relpages * current_setting('seq_page_cost')::DECIMAL whole_file
    FROM pg_class c
        JOIN pg_stats s ON s.tablename = c.relname
    WHERE c.relname = 'mytable'
        ), 
   decode_block AS (
    SELECT 
        current_setting('cpu_tuple_cost') one_row,
        c.reltuples * current_setting('cpu_tuple_cost')::DECIMAL whole_table
    FROM pg_class c
        JOIN pg_stats s ON s.tablename = c.relname
    WHERE c.relname = 'mytable'),
    filter_rows AS (
    SELECT 
        current_setting('cpu_operator_cost') one_row,
        c.reltuples * current_setting('cpu_operator_cost')::DECIMAL  whole_table
    FROM pg_class c
        JOIN pg_stats s ON s.tablename = c.relname
    WHERE c.relname = 'mytable'
) 
SELECT 
    'seq_scan=>',
    r.whole_file + d.whole_table seq_cost,
    'filter=>',
    f.one_row, f.whole_table,
    'whole=>',
    r.whole_file + d.whole_table + f.whole_table
FROM read_block r, decode_block d, filter_rows f 
```
33 850

The costs match.


## Table random access

What is the estimated cost ? 
```postgresql
EXPLAIN 
SELECT * FROM mytable WHERE ctid = '(0,1)'
```

## Table random access

What is the estimated cost ? 
```postgresql
EXPLAIN 
SELECT * FROM mytable WHERE ctid = '(0,1)'
```


> Random access to durable storage is normally much more expensive than four times sequential access. However, a lower default is used (4.0) because the majority of random accesses to storage, such as indexed reads, are assumed to be in cache. Also, the latency of network-attached storage tends to reduce the relative overhead of random access.

> Although the system will let you set random_page_cost to less than seq_page_cost, it is not physically sensible to do so. However, setting them equal makes sense if the database is entirely cached in RAM, since in that case there is no penalty for touching pages out of sequence. Also, in a heavily-cached database you should lower both values relative to the CPU parameters, since the cost of fetching a page already in RAM is much smaller than it would normally be.

https://www.postgresql.org/docs/current/runtime-config-query.html

## More

[Hironobu Suzuki](https://www.interdb.jp/pg/pgsql03/02.html)