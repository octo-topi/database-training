# Costs

## Table access (in cache)

### Sequential scan

Q: What happens when reading a whole table ?

A : The following:
- read all table blocks from cache
- for each block:
  - access each row using tuple pointer
  - for each tuple, check if it visible
  - if yes, return it 


#### Read buffers

As we cannot know if the block will be in the cache, PostgreSQL assume that it will have to read it from the disk.

The cost of this operation, named `seq_page_cost`, is assigned the arbitrary value 1.
It is taken as the reference for all other costs' parameter.
```postgresql
SHOW seq_page_cost 
```
1


#### Get rows from buffers

We can know how any rows there are in each block ... if we read the block and check the item pointer.
We don't want to do that - we'll rely on the row count from the stats.

Applying an operator to a row has a cost named `cpu_tuple_cost` which is 1/100 of `seq_page_cost`.
```postgresql
SHOW cpu_tuple_cost
```
0.01

#### Sum up

Let's create a table.
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (autovacuum_enabled = FALSE);

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


#### Does it scale ?

Q: Can sequential scan be pipelined ? Does it scale ?

A: Yes, we can read a bunch or rows, return them to the client, and process another batch.
It scales, its complexity is O(n).

### Table direct access

What is the estimated cost ? 
```postgresql
EXPLAIN 
SELECT * FROM mytable WHERE ctid = '(0,1)'
```

### Table random access

You can only get it using an index.

```postgresql
SHOW random_page_cost 
```

What is the estimated cost ? 
```postgresql
EXPLAIN 

```


> Random access to durable storage is normally much more expensive than four times sequential access. However, a lower default is used (4.0) because the majority of random accesses to storage, such as indexed reads, are assumed to be in cache. Also, the latency of network-attached storage tends to reduce the relative overhead of random access.

> Although the system will let you set random_page_cost to less than seq_page_cost, it is not physically sensible to do so. However, setting them equal makes sense if the database is entirely cached in RAM, since in that case there is no penalty for touching pages out of sequence. Also, in a heavily-cached database you should lower both values relative to the CPU parameters, since the cost of fetching a page already in RAM is much smaller than it would normally be.

[Reference](https://www.postgresql.org/docs/current/runtime-config-query.html)


## Other operations (in private process memory)

### Filter

Q: What happens when reading a whole table with a filter?
A : The same as in sequential table scan, add then a filter is applied

Q: Where does this happens ? In which memory ?
A: Buffer from seq scan are stored in shared_buffers, filtered rows are stored in the backend process memory.

#### Filter

As we saw in [filtering](../filtering), we can estimate how many rows we will get.
However, we want here the cost of the operation: all visible rows will have to be filtered. 

Applying an operator to a row has a cost named `cpu_operator_cost` which is 1/400 of `seq_page_cost`.
```postgresql
SHOW cpu_operator_cost
```
0.0025

#### Sum up

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
EXPLAIN ANALYZE
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


#### Does it scale ?

Q: Can filter on seq scan be pipelined ? Does it scale ?

A: Yes, the filter itself can be pipelined, and is operating on a pipelined operation, seq scan. 
It scales, its complexity is O(n).


### Data transform

If your query keep the table column as is, no work has to be done.
But if you change it in any way, there is some work, and each work has a cost. 

```postgresql
SELECT 
     id
    ,id*10                 multiply 
    ,ABS(id)               call_function 
    ,id::TEXT              casting
    ,CASE id WHEN 10 THEN 'ten' ELSE 'not ten' END
FROM mytable
```

The cost is the same as for a filter : `cpu_operator_cost` which is 1/400 of `seq_page_cost`.
```postgresql
SHOW cpu_operator_cost
```
0.0025

Let's create a table.
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);

TRUNCATE TABLE mytable;

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;

SELECT * FROM mytable;
```

What is the cost for multiply ?
```postgresql
SELECT 
    id*10
FROM mytable
```

Let's compute the cost ourselves : there is 1 transform.
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
    transform_rows AS (
    SELECT 
        current_setting('cpu_operator_cost') one_row,
        -- operator count
        c.reltuples * 1 * current_setting('cpu_operator_cost')::DECIMAL  whole_table
    FROM pg_class c
        JOIN pg_stats s ON s.tablename = c.relname
    WHERE c.relname = 'mytable'
) 
SELECT 
    'seq_scan=>',
    r.whole_file + d.whole_table seq_cost,
    'transform=>',
    t.one_row, t.whole_table,
    'whole=>',
    r.whole_file + d.whole_table + t.whole_table
FROM read_block r, decode_block d, transform_rows t 
```
16 925

Let's check it
```postgresql
EXPLAIN
SELECT 
    id*10
FROM mytable
```

```text
Seq Scan on mytable  (cost=0.00..16925.00 rows=1000000 width=4)
```

There is no separate cost for transform, all is listed under `Seq scan`.


The cost for transform should be computed using `Sq scan` without transform.
```postgresql
SELECT 16_925 - 14_425
```
2 500, all good


Keep in mind the cost itself does not take into account the result set length.
You can keep one column of the table, or a hundred, the cist is still the same. 
```postgresql
EXPLAIN 
SELECT id, id, id , id, id , id, id, id, id, id 
FROM mytable
```

```text
Seq Scan on mytable  (cost=0.00..14425.00 rows=1000000 width=40)
```

Therefore, you may get different execution time for the same cost.
If query many big columns, you'll have to store them in memory - and if you run out of memory, you'll use temp file on fs, which are slower.

### Using many rows

Till now, we saw data transform on each row.

Some operations, called aggregation, do not transform rows.
They take many rows and output one single row :
- counting;
- minimum, maximum.


Let's check it
```postgresql
EXPLAIN
SELECT 
   SUM(id)
FROM mytable
```

A new node appears `aggregate`
```text
Aggregate  (cost=16925.00..16925.01 rows=1 width=4)                 
 ->  Seq Scan on mytable  (cost=0.00..14425.00 rows=1000000 width=4)
```

The aggregation cost can't be read directly, you should subtract the cost of `Aggregate` from `Seq Scan`.
```postgresql
SELECT 16_925 - 14_425
```
2500

You can use this [visual](https://explain.dalibo.com/plan/1g2hf652b4g876c9) aid.

#### Does it scale ?

Q: Which operations can be pipelined, and therefore are scalable ?
- counting;
- minimum, maximum.

A: All can be pipelined, there is no need to get all rows first, and then to apply the function.

### Sorting

Sorting does not transform rows, but there is work to do, and each work has its cost.

```postgresql
EXPLAIN
SELECT 
   id
FROM mytable
ORDER BY id DESC
```

A `Sort` node appears
```text
Sort  (cost=138110.89..140610.89 rows=1000000 width=4)
  Sort Key: id DESC
  ->  Seq Scan on mytable  (cost=0.00..14425.00 rows=1000000 width=4)
```

The total cost is Sort  140 610, the sort cost is
```postgresql
SELECT 140_610 - 14_425
```
126 185

It is huge.

```postgresql
SELECT TRUNC(((140_610 - 14_425) / 140_610::DECIMAL) * 100) || '%'
```
90 % of the cost is sorting, not reading data.


#### Does it scale ?

Q: Can sorting can be pipelined, is it scalable ?

A: It cannot be pipelined.
You had to fetch all rows first, sort them, then return the results to the client.
It therefore does not scale.

PostgreSQL can use 2 algorithms:
- memory:
  - quicksort,
  - top-N heapsort
- disk: external merge sorting. 

Their complexity is O(n log n).

Reference: PostgreSQL Internals, Part IV - Query execution - Sorting and merging / Sorting

## More

Table seq scan nitty-gritty cost calculations are available in [Hironobu Suzuki](https://www.interdb.jp/pg/pgsql03/02.html).