# Solutions

## Fixed-size types

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer,
    name CHARACTER(100)
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id, name)
SELECT n, 
       REPEAT('a',n)
FROM generate_series(1, 100) AS n;
```


```postgresql
SELECT id, ctid, name
FROM mytable
WHERE 1=1
LIMIT 3
```

| id | ctid    | name |
|:---|:--------|:-----|
| 1  | \(0,1\) | b    |
| 2  | \(0,2\) | cc   |
| 3  | \(0,3\) | ddd  |

```postgresql
SELECT 
    pnt.lp_off row_start,
    pnt.lp_len row_length
FROM heap_page_items(get_raw_page('mytable', 0)) pnt
ORDER BY pnt.lp ASC
LIMIT 3
```

| row\_start | row\_length |
|:-----------|:------------|
| 8056       | 129         |
| 7920       | 129         |
| 7784       | 129         |


```postgresql
SELECT     
    (ctid::text::point)[0]::bigint AS block_number,
    COUNT(1) row_count
FROM mytable
GROUP BY block_number
ORDER BY block_number
LIMIT 5
```

| block\_number | row\_count |
|:--------------|:-----------|
| 0             | 51         |
| 1             | 38         |
| 2             | 11         |

Size
```postgresql
SELECT 
    pg_size_pretty(pg_table_size('mytable'))
```
48 kB

## Variable-size types

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer,
    name TEXT
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO mytable (id, name)
SELECT n, 
       REPEAT('a',n)
FROM generate_series(1, 100) AS n;
```

```postgresql
SELECT id, ctid, name
FROM mytable
WHERE 1=1
LIMIT 3
```

| id | ctid    | name |
|:---|:--------|:-----|
| 1  | \(0,1\) | b    |
| 2  | \(0,2\) | cc   |
| 3  | \(0,3\) | ddd  |


```postgresql
SELECT 
    pnt.lp_off row_start,
    pnt.lp_len row_length
FROM heap_page_items(get_raw_page('mytable', 0)) pnt
ORDER BY pnt.lp ASC
LIMIT 10
```

| row\_start | row\_length |
|:-----------|:------------|
| 8160       | 30          |
| 8128       | 31          |
| 8096       | 32          |
| 8056       | 33          |
| 8016       | 34          |
| 7976       | 35          |
| 7936       | 36          |



```postgresql
SELECT     
    (ctid::text::point)[0]::bigint AS block_number,
    COUNT(1) row_count
FROM mytable
GROUP BY block_number
ORDER BY block_number
LIMIT 5
```

| block\_number | row\_count |
|:--------------|:-----------|
| 0             | 75         |
| 1             | 25         |


Size
```postgresql
SELECT 
    pg_size_pretty(pg_table_size('mytable'))
```

48 kB

## Compression

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  INTEGER,
    name TEXT
) WITH (AUTOVACUUM_ENABLED = FALSE);

ALTER TABLE mytable ALTER COLUMN name SET STORAGE plain;

INSERT INTO mytable (id, name)
SELECT n, 
       REPEAT(CHR(ascii('a')  + n),n)
FROM generate_series(1, 100) AS n;
```



```postgresql
SELECT 
    pnt.lp_off row_start,
    pnt.lp_len row_length
FROM heap_page_items(get_raw_page('mytable', 0)) pnt
ORDER BY pnt.lp ASC
LIMIT 3
```

| row\_start | row\_length |
|:-----------|:------------|
| 8160       | 30          |
| 8128       | 31          |
| 8096       | 32          |



```postgresql
SELECT     
    (ctid::text::point)[0]::bigint AS block_number,
    COUNT(1) row_count
FROM mytable
GROUP BY block_number
ORDER BY block_number
LIMIT 3
```

| block\_number | row\_count |
|:--------------|:-----------|
| 0             | 75         |
| 1             | 25         |



Size
```postgresql
SELECT 
    pg_size_pretty(pg_table_size('mytable'))
```
48 kB


```postgresql
SELECT 
    attname           "column", 
    atttypid::regtype "type",
    CASE attstorage
        WHEN 'p' THEN 'nothing'
        WHEN 'm' THEN 'compress in place, then toast if needed'
        WHEN 'e' THEN 'toast uncompressed'
        WHEN 'x' THEN 'toast compressed'
    END AS operation
FROM pg_attribute
WHERE attrelid = 'mytable'::regclass AND attnum > 0;
```


## Table content

Get table size.
```postgresql
SELECT 
    pg_size_pretty(pg_table_size('flights')) table_size
```

| table\_size |
|:------------|
| 21 MB       |


```postgresql
ANALYZE VERBOSE flights
```

How many blocks ?
```postgresql
SELECT 
    relpages  block_count,
    reltuples row_count
FROM pg_class WHERE relname = 'flights';
```

| block\_count | row\_count |
|:-------------|:-----------|
| 2624         | 214867     |

```postgresql
CREATE EXTENSION IF NOT EXISTS pageinspect;
```

Get row length
```postgresql
SELECT 
    pnt.lp_len row_length
FROM heap_page_items(get_raw_page('flights', 0)) pnt
LIMIT 5
```

| row\_length |
|:------------|
| 86          |
| 86          |
| 86          |
| 86          |
| 86          |


The size is the same, because all variable types are toasted.

```postgresql
SELECT 
    attname           "column", 
    atttypid::regtype "type",
    CASE attstorage
        WHEN 'p' THEN 'nothing'
        WHEN 'm' THEN 'compress in place, then toast if needed'
        WHEN 'e' THEN 'toast uncompressed'
        WHEN 'x' THEN 'toast compressed'
    END AS operation
FROM pg_attribute
WHERE attrelid = 'tickets'::regclass AND attnum > 0;
```

```postgresql
ANALYZE flights;
```


Get usage
```postgresql
SELECT
     'events:'
     ,stt.n_tup_ins                     insert_count
     ,stt.n_tup_upd + stt.n_tup_hot_upd update_count
     ,stt.n_tup_del                     delete_count
     ,stt.last_seq_scan                 last_read
     ,stt.seq_tup_read                  read_count
--,stt.*
FROM pg_stat_user_tables stt
WHERE 1=1
  AND relname = 'flights'
;
```

```postgresql
SELECT heap_blks_read, toast_blks_hit
FROM pg_statio_user_tables s
WHERE s.relname = 'flights'
ORDER BY pg_relation_size(relid) DESC;
```