# More


## Metamodel


```postgresql
CREATE INDEX mytable_id ON mytable(id);
```

You can find index definition in `pg_indexes`.
```postgresql
SELECT
        ndx.indexname ndx_nm
       ,ndx.tablename tbl_nm
       ,ndx.indexdef  dfn
FROM pg_indexes ndx
WHERE 1=1
    AND ndx.tablename = 'mytable'
    AND ndx.indexname = 'mytable_id'
;
```

| ndx\_nm     | tbl\_nm | dfn                                                           |
|:------------|:--------|:--------------------------------------------------------------|
| mytable\_id | mytable | CREATE INDEX mytable\_id ON public.mytable USING btree \(id\) |


You can find its type in a dedicated column in `pg_index`.
```postgresql
SELECT
    'index=>'
    ,cls.relname       index_name
    ,ndx.indisvalid    is_valid
    ,ndx.indisunique   is_unique
    ,ndx.indisprimary is_primary
    ,ndx.indkey
FROM pg_index ndx
      INNER JOIN pg_class cls ON ndx.indexrelid = cls.oid
WHERE 1=1
    AND cls.relname  = 'mytable_id'
;
```


## Statistics


There is, of, course, statistics on index access.
```postgresql
SELECT
    ndx_stt.relname      tbl_nm,
    ndx_stt.indexrelname ndx_nm,
    'statistics=>',
    ndx_stt.idx_scan     usage_count, -- Number of index scans initiated on this index
    ndx_stt.idx_tup_read,             -- Number of index entries returned by scans on this index
    ndx_stt.idx_tup_fetch             -- Number of live table rows fetched by simple index scans using this index
FROM pg_stat_all_indexes ndx_stt
WHERE 1 = 1
  AND ndx_stt.schemaname = 'mytable'
--   AND indexrelname NOT LIKE '%pkey%'
ORDER BY
   idx_tup_fetch DESC,
   idx_tup_read DESC
;
```