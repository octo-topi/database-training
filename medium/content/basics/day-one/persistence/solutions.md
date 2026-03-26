# Solutions

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