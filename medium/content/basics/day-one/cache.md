# Cache

Use `BUFFERS` option in execution plan

## Setup

Activate extensions
```postgresql
CREATE EXTENSION pg_buffercache;
CREATE EXTENSION pg_prewarm;
```

## Monitor cache

Cache overview
```postgresql
SELECT 
    pg_size_pretty(c.buffers_used * 8 * 1024::numeric) used,
    pg_size_pretty(c.buffers_unused* 8 * 1024::numeric) free,
    c.buffers_dirty  dirty_count,
    c.buffers_pinned pinned_count,
    TRUNC(c.usagecount_avg) || ' %' used
FROM pg_buffercache_summary() c;

SELECT pg_buffercache_evict() 
```

Cache entries + table
Table with most cache entries
```postgresql
SELECT
    c.relname object_name,
    count(*) AS buffer_count,
    pg_size_pretty(count(*) * 1024 * 8) buffer_size
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
    AND c.relname NOT LIKE 'pg_%'
--     AND c.relname = 'mytable'
GROUP BY c.relname
ORDER BY 2 DESC
LIMIT 10;
```

## Evict from cache

Evict from cache
```postgresql
SELECT
    pg_buffercache_evict(b.bufferid)
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d  ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
--    AND c.relname NOT LIKE 'pg_%'
  AND c.relname = 'mytable';

-- SELECT pg_buffercache_evict(1011);
```

## Loading

Load cache
```postgresql
SELECT pg_prewarm('mytable');
```

## Run query without cache

Query table
```postgresql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, ctid 
FROM mytable
```

## Run query with cache

Load cache
```postgresql
SELECT pg_prewarm('mytable');
```

Rows per block
```postgresql
SELECT
    (ctid::text::point)[0]::bigint AS block,
    COUNT(1) rows_per_block
FROM mytable
GROUP BY (ctid::text::point)[0]::bigint
;
```

