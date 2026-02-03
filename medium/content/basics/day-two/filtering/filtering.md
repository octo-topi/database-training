# Filtering - Table data statistics

## No filter

Let's create a single-row table
```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (autovacuum_enabled = FALSE);

INSERT INTO mytable (id) VALUES (-1);
```

Suppose we want to query the table, as is.
How can we know many rows will it return, without running the query ?
```text
SELECT id 
FROM mytable
```

We can use `pg_stat_user_tables`
```postgresql
SELECT
   stt.n_live_tup row_count
FROM pg_stat_user_tables stt
WHERE 1=1
   AND relname = 'mytable'
;
```
1

This figure, 1 row, is called the table `cardinality`.

What if we delete it ?
```postgresql
DELETE FROM mytable
WHERE id =-1
```

We still have the right figure
```postgresql
SELECT
   stt.n_live_tup row_count
FROM pg_stat_user_tables stt
WHERE 1=1
   AND relname = 'mytable'
;
```
0

Is there other table that store tuple count ?
```postgresql
SELECT
     'column'
     ,c.table_name
     ,c.column_name
FROM
     information_schema.columns c
WHERE 1=1
    AND c.table_schema = 'pg_catalog'
    AND c.column_name ILIKE '%tup%'
ORDER BY
    c.table_name, c.column_name ASC
;
```

Yes, `p_class`. Let's query it.
```postgresql
SELECT
    reltuples
FROM pg_class 
WHERE 1=1
   AND relname = 'mytable'
;
```
-1

Look like it is not up-to-date ...


## Basic filter

Now, if we query the table with a filter
How can we know how many rows it will return without running the query ?
```postgresql
SELECT id 
FROM mytable
WHERE id=1
```

We know no rows will be returned, because we inserted no rows for id=1.
We need insight into the data, without recording everything that happened to the table. 
How can PostgreSQL do that ? It will compute statistics on the table from time to time. 

Let's query  `pg_statistic` table.
```postgresql
SELECT * FROM pg_statistic s
WHERE s.starelid = 'mytable'::regclass
```
[Reference](https://www.postgresql.org/docs/current/catalog-pg-statistic.html)

Look like there are no statistics.

Getting statistics involve some sampling, visiting some of the table's rows.

This is costly, it is done:
- automatically, part of [auto-vacuuming](https://www.postgresql.org/docs/17/runtime-config-autovacuum.html);
- manually by issuing `ANALYZE`.

```postgresql
ANALYZE VERBOSE mytable
```

You get an output which remind you how many resources you use.
```text
analyzing "public.mytable"
"mytable": scanned 1 of 1 pages, containing 0 live rows and 1 dead rows; 0 rows in sample, 0 estimated total rows
finished analyzing table "database.public.mytable"
I/O timings: read: 0.000 ms, write: 0.000 ms
avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
buffer usage: 5 hits, 0 reads, 0 dirtied
```

The last analyze time is available in `pg_stat_user_tables`.
```postgresql
SELECT last_analyze, last_autoanalyze
FROM pg_stat_user_tables t 
WHERE t.relname = 'mytable'
```

| last\_analyze                     | last\_autoanalyze |
|:----------------------------------|:------------------|
| 2026-02-02 14:25:08.567033 +00:00 | null              |


Statistics are now available.
```postgresql
SELECT * FROM pg_statistic s
WHERE s.starelid = 'mytable'::regclass
```

Look like there is no statistics if the table has no live tuples.
Let's add some.
```postgresql
INSERT INTO mytable (id) VALUES (-1);
ANALYZE VERBOSE mytable;
SELECT * FROM pg_statistic s
WHERE s.starelid = 'mytable'::regclass;
```

They are easier to read using this view.
```postgresql
SELECT
    s.*
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'id'
```

Most figures are not set.

Let's add many rows - with the same value.
```postgresql
INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 10_000_000) AS n;

ANALYZE mytable;
```

Now query the stats.
```postgresql
SELECT
     s.avg_width         size_bytes
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
     ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
    --,s.*
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'id'
```

| size\_bytes | distinct\_values | most\_common\_values\_count | most\_common\_values\_frequency | null\_ratio |
|:------------|:-----------------|:----------------------------|:--------------------------------|:------------|
| 4           | 1                | {1}                         | {1.00000000}                    | 0%          |


If we check [the docs](https://www.postgresql.org/docs/current/view-pg-stats.html), we can see :
- the average attribute size is 4 bytes ;
- there is one distinct value;
- the frequency of value `1` is 1 ( `most_common_value_frequency=1` = all rows have the value `1` );
- there is no `NULL` value (`null_frac=0`).

So if we run this query, we know we will get all table's rows.
```postgresql
SELECT id 
FROM mytable
WHERE id=1
```

We will get that many rows.
```postgresql
SELECT
    c.reltuples * s.most_common_freqs[1] row_count
FROM pg_class c
    JOIN pg_stats s ON s.tablename = c.relname
WHERE 1=1
    AND c.relname = 'mytable'
```
10 000 047

The count is off by 47 rows, this is perfectly acceptable. 


In this query, `id = 1` is called a predicate
```postgresql
SELECT id 
FROM mytable
WHERE id=1
```

The ratio of rows that are kept after the filter is called the `selectivity`.
```postgresql
SELECT 
    ((SELECT COUNT(*) FROM mytable WHERE id=1)::DECIMAL / (SELECT COUNT(*) FROM mytable)::DECIMAL) selectivity
```

The selectivity is all about the data: here, teh frequency of the selected value, 1, is the selectivity. 

## What about NULL ?

Let's insert rows with more interesting repartition, including NULL: 
- 10 % 1
- 40 % 2
- 50 % NULL

```postgresql
TRUNCATE mytable;

INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 10/100::DECIMAL * 1_000_000) AS n;
   
INSERT INTO mytable (id)
SELECT 2
FROM generate_series(1, 40/100::DECIMAL * 1_000_000) AS n;

INSERT INTO mytable (id)
SELECT NULL
FROM generate_series(1, 50/100::DECIMAL * 1_000_000) AS n;

ANALYZE VERBOSE mytable;

SELECT COUNT(*) FROM mytable;
SELECT * FROM mytable;
```

Let's see
```postgresql
SELECT
     s.avg_width         size_bytes
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
     ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'id'
```

| size\_bytes | distinct\_values | most\_common\_values\_count | most\_common\_values\_frequency          | null\_ratio |
|:------------|:-----------------|:----------------------------|:-----------------------------------------|:------------|
| 4           | 2                | {2,1}                       | {0.3975333273410797,0.09946666657924652} | 50%         |


We've got 2 distinct values:
- 2 on `39%` of the rows; 
- 1 on `9,94%` of the rows.

NULL (which is not a value) makes for `50%` of the rows.

If we run this query, we know we will 40% of table rows.
```postgresql
SELECT id 
FROM mytable
WHERE id=2
```

That is:
```postgresql
SELECT
    TRUNC(c.reltuples * s.most_common_freqs[1]) row_count
FROM pg_class c
    JOIN pg_stats s ON s.tablename = c.relname
WHERE 1=1
    AND c.relname = 'mytable'
```
401 566

If we run this query, we will have about 50% of table rows.
```postgresql
SELECT id 
FROM mytable
WHERE id IS NULL
```

That is:
```postgresql
SELECT
    TRUNC(c.reltuples * s.null_frac) row_count
FROM pg_class c
    JOIN pg_stats s ON s.tablename = c.relname
WHERE 1=1
    AND c.relname = 'mytable'
```
496 466


## Histograms

The type of statistics we saw, stored in `most_common_value` and `most_common_freqs`, is called MCV for "Most Common Value".
It is useful where there is a few distinct values. What if values are so different they are unique ?

We still what to know how many rows will match.
```postgresql
SELECT id 
FROM mytable
WHERE id = 50
```

Let's insert a million single values.
```postgresql
TRUNCATE mytable;

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;

SELECT COUNT(*) FROM mytable;
SELECT * FROM mytable;
```

Let's see
```postgresql
SELECT
     s.avg_width         size_bytes
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
     ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'id'
```

There is no MCV stats: 

| size\_bytes | distinct\_values | most\_common\_values\_count | most\_common\_values\_frequency | null\_ratio |
|:------------|:-----------------|:----------------------------|:--------------------------------|:------------|
| 4           | -1               | null                        | null                            | 0%          |


There are histogram stats.
```postgresql
SELECT
     s.avg_width         size_bytes
    ,s.n_distinct        distinct_values
    ,s.histogram_bounds
    , cardinality(s.histogram_bounds) bucket_count
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'id'
```

| size\_bytes | distinct\_values | histogram\_bounds                                     | bucket\_count |
|:------------|:-----------------|:------------------------------------------------------|:--------------|
| 4           | -1               | {46,10416,19805,30397,40551,...,979854,990149,999946} | 101           |


Each bucket contains roughly the same count of rows.

There can be no more that this many buckets, unless you change the setting (you can do it on a table basis). 
```postgresql
SHOW default_statistics_target 
```
100


So what about our query ?
```postgresql
SELECT id 
FROM mytable
WHERE id = 1
```

Each bucket contains around 10 000 rows
```postgresql
SELECT
    TRUNC(c.reltuples /  cardinality(s.histogram_bounds)) row_per_bucket     
FROM pg_class c
    JOIN pg_stats s ON s.tablename = c.relname
WHERE 1=1
    AND c.relname = 'mytable'
```
9900 rows

The first bucket, contains our value `50`.
It also covers more value, around 10 000 values
```postgresql
SELECT 10416 - 46 bucket1_size
```
10370 

If we consider equiprobability (there are as many rows for 50 than for 10416)
The row count per value is  
```postgresql
WITH bucket AS (
    SELECT 
        TRUNC(c.reltuples /  cardinality(s.histogram_bounds)) row_per_bucket,
        (10416 - 46) first_bucket_size
    FROM  pg_class c
        JOIN pg_stats s ON s.tablename = c.relname
    WHERE c.relname = 'mytable'
    ) 
SELECT 
    ROUND(b.row_per_bucket / b.first_bucket_size) AS row_count
FROM bucket b
```
1 row




## Several columns

What happens if our table has 2 columns ?
```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id    INTEGER,
    valid BOOLEAN
) WITH (autovacuum_enabled = FALSE);

INSERT INTO mytable (id, valid)
SELECT 1, n%2=0
FROM generate_series(1, 500_000) AS n;
   
INSERT INTO mytable (id, valid)
SELECT 2, FALSE
FROM generate_series(500_000, 1_000_000) AS n;

SELECT * FROM mytable WHERE id = 1;
SELECT * FROM mytable WHERE id = 2;

ANALYZE VERBOSE mytable;
```

Let's see
```postgresql
SELECT
    s.attname
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
     ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
```

We've got the same distribution for both columns 

| distinct\_values | most\_common\_values\_count | most\_common\_values\_frequency          | null\_ratio |
|:-----------------|:----------------------------|:-----------------------------------------|:------------|
| 2                | {2,1}                       | {0.5000666379928589,0.4999333322048187}  | 0%          |
| 2                | {f,t}                       | {0.7533666491508484,0.24663333594799042} | 0%          |

We can see: 
- `id` has 2 values, 1 and 2, 50% each
- `valid` has 2 values, false 75% and true on 25%

But we can't see that all `2` have false, and that 1 have 50/50.  
```postgresql
SELECT id, valid, count(1) FROM mytable GROUP BY id, valid
order by id;
```

| id | valid | count  |
|:---|:------|:-------|
| 1  | true  | 250000 |
| 1  | false | 250000 |
| 2  | false | 500001 |


To prevent this, we can create a custom statistic.
```postgresql
CREATE STATISTICS id_and_validity ON id, valid FROM mytable;
ANALYZE VERBOSE mytable;
```

Let's see
```postgresql
SELECT
    s.attname
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
     ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
```

They do not appear here !
There is no view available to get them, but they are computed nonetheless.

Let's see
```postgresql
SELECT
     s.attnames
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
FROM pg_stats_ext s
WHERE 1=1
    AND s.tablename = 'mytable'
```

| attnames   | distinct\_values | most\_common\_values\_count | most\_common\_values\_frequency                               |
|:-----------|:-----------------|:----------------------------|:--------------------------------------------------------------|
| {id,valid} | {"1, 2": 3}      | {{2,f},{1,t},{1,f}}         | {0.50010000000000000,0.25380000000000000,0.24610000000000000} |

There are 3 values:
- `(1, TRUE)`  : 25% 
- `(1, FALSE)` : 25%
- `(2, FALSE)` : 50%  


[Reference](https://www.postgresql.org/docs/current/view-pg-stats-ext.html)

## Filter on expression

Let's create a text dataset
```postgresql
DROP TABLE mytable;

CREATE TABLE mytable (
    id    INTEGER,
    name  TEXT
) WITH (autovacuum_enabled = FALSE);

TRUNCATE mytable;

INSERT INTO mytable (id, name)
SELECT n, CHR(ASCII('B') + (random() * 25)::integer) || 'LISABETH'
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;
```

Name always start with a different letter.
```postgresql
SELECT id, name FROM mytable LIMIT 3;
```
| id | name      |
|:---|:----------|
| 1  | KLISABETH |
| 2  | XLISABETH |
| 3  | XLISABETH |


Suppose we want to query always the name starting with a vowel 
```postgresql
SELECT id, name 
FROM mytable 
WHERE SUBSTRING(name,1,1) IN ('A','E','I','O','U','Y') 
LIMIT 5; 
```

| id | name      |
|:---|:----------|
| 5  | OLISABETH |
| 8  | YLISABETH |
| 12 | ILISABETH |
| 13 | OLISABETH |
| 23 | YLISABETH |


We will repeatedly filter on first character.
How can PostgreSQL know how many rows will be returned ?


### Virtual column

We can create a virtual column. 
```postgresql

ALTER TABLE mytable ADD COLUMN first_letter BOOLEAN
GENERATED ALWAYS AS (
    SUBSTRING(name,1,1) IN ('A','E','I','O','U','Y')
) VIRTUAL;

ANALYZE VERBOSE mytable(first_letter);
```
[Reference](https://www.postgresql.org/docs/current/ddl-generated-columns.html)


```postgresql
SELECT
    s.attname
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
     ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
```

### Materialized column

There is no statistics, we need to materialize the column.

```postgresql
DROP TABLE mytable;
CREATE TABLE mytable (
    id    INTEGER,
    name  TEXT,
    first_letter BOOLEAN GENERATED ALWAYS AS (
        SUBSTRING(name,1,1) IN ('A','E','I','O','U','Y')
    ) STORED
) WITH (autovacuum_enabled = FALSE);

INSERT INTO mytable (id, name)
SELECT n, CHR(ASCII('B') + (random() * 25)::integer) || 'LISABETH'
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;
```

There are now some statistics
```postgresql
SELECT
    s.attname
    ,s.n_distinct        distinct_values
    ,s.most_common_vals  most_common_values_count
    ,s.most_common_freqs most_common_values_frequency
     ,TRUNC(s.null_frac * 100) || '%'  null_ratio 
FROM pg_stats s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.attname = 'first_letter'
```

| attname       | distinct\_values | most\_common\_values\_count | most\_common\_values\_frequency          | null\_ratio |
|:--------------|:-----------------|:----------------------------|:-----------------------------------------|:------------|
| first\_letter | 2                | {f,t}                       | {0.8031333088874817,0.19686666131019592} | 0%          |


But this use space: statistics relies on sampling, not on all rows.


### Expression statistics

We can rather create an expression custom statistic.

```postgresql
DROP STATISTICS first_letter_is_vowel;
CREATE STATISTICS first_letter_is_vowel ON (SUBSTRING(name, 1, 1) IN ('A','E','I','O','U')::BOOLEAN) FROM mytable;
ANALYZE VERBOSE mytable;
```

Let's see
```postgresql
SELECT
     s.n_distinct        distinct_values
    ,s.most_common_vals   most_common_values_count
    ,s.most_common_freqs  most_common_values_frequency
    ,s.most_common_freqs[1] most_common_values_frequency
FROM pg_stats_ext_exprs s
WHERE 1=1
    AND s.tablename = 'mytable'
    AND s.statistics_name = 'first_letter_is_vowel'
```

We see that only 15% rows from the sample starts with a vowel. 

| distinct\_values | most\_common\_values\_count | most\_common\_values\_frequency        | most\_common\_values\_frequency |
|:-----------------|:----------------------------|:---------------------------------------|:--------------------------------|
| 2                | {f,t}                       | {0.84006667137146,0.15993332862854004} | 0.8400667                       |

