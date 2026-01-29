# More


## More stats 

`pg_stat_io` has a bunch of useful information.

[Source](https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-IO-VIEW)


[Source](https://www.cybertec-postgresql.com/en/pg_stat_io-postgresql-16-performance/)


You can reset all stats 
```postgresql
SELECT pg_stat_reset_shared()
```

Or this one
```postgresql
SELECT pg_stat_reset_shared('io')
```

### buffer ring

Context:
- `bulkread` and `bulkwrite` relate to buffer-ring use
- `normal` relate to shared buffers use

```postgresql
SELECT 'I/O=>' _
     , io.backend_type
     , io.object
     , io.context
     , 'read:' _
     , io.reads          blocks
     , pg_size_pretty(io.read_bytes)  size
     , io.read_time      elapsed
     , 'w=>OS' _ -- write PG cache => OS cache
     , io.writes         blocks
     , pg_size_pretty(io.write_bytes)  size
     , io.write_time     elapsed
     , 'w=>disk' _ -- write OS cache => disk
     , io.writebacks     block
     , io.writeback_time elapsed
     --, 'pg_stat_io'
     --, io.*
FROM pg_stat_io io
WHERE 1 = 1
  --AND (io.reads > 0 OR io.writes > 0)
--   AND io.backend_type IN (
--                           'checkpointer'
--                           ,'background writer'
--                           ,'client backend'
--     )
ORDER BY io.writes DESC
```

###  cache hit, cache eviction, datafile grows



```postgresql
SELECT DISTINCT backend_type FROM pg_stat_io
ORDER BY 1
```

| backend\_type       |
|:--------------------|
| autovacuum launcher |
| autovacuum worker   |
| background worker   |
| background writer   |
| checkpointer        |
| client backend      |
| io worker           |
| slotsync worker     |
| standalone backend  |
| startup             |
| walreceiver         |
| walsender           |
| walsummarizer       |
| walwriter           |



```postgresql
SELECT
    'I/O=>'
    ,io.backend_type
    ,io.object
    ,io.context
    ,''
    ,io.evictions
    ,io.hits
    ,io.extends
    ,'pg_stat_io'
    ,io.*
FROM
 pg_stat_io io
WHERE 1=1
    AND io.backend_type = 'client backend'
--    AND io.backend_type IN ('checkpointer', 'background writer', 'client backend')
    --AND extends > 0
```

## OS cache
We can clear the OS cache and check how this affects performance.