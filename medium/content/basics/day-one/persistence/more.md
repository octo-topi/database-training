# More on storage

## Auto-vacuum

### Why

For pedagogic purposes, we disabled auto-vacuum on the table. 
```postgresql
CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
```

We run it manually.
```postgresql
VACUUM VERBOSE mytable;
```

You shall not do this on production.
Instead, you should make sure auto-vacuum is properly configured and runs. 

The last auto-vacuum run is available in `pg_stat_user_tables`.
```postgresql
SELECT last_autovacuum
FROM pg_stat_user_tables t 
WHERE t.relname = 'mytable'
```

Let's see how to configure it.

### Start on update or delete

These parameters control when autovacuum starts because of update or delete, aka dead tuples:
- autovacuum_naptime : minimum delay between autovacuum - default is one minute
- autovacuum_vacuum_threshold : minimum number of updated or deleted tuples - default : 50
- autovacuum_vacuum_scale_factor : fraction of the table size - default is 0.2 (20% of table size).

In short, by default:
- each minute, if the last autovacuum ended more than a minute ago, the table statistics are queried;
- is there (50 tuples + 20% of the rows of the table) as dead tuples ?
- if yes, start an auto-vacuum.

```postgresql
WITH settings AS (
  SELECT 
       current_setting('autovacuum_vacuum_threshold')::INT threshold,
       current_setting('autovacuum_vacuum_scale_factor')::DECIMAL scale_factor
)
SELECT 
    t.n_dead_tup,
    c.reltuples * s.scale_factor + s.threshold triggers_at,
    (t.n_dead_tup::DECIMAL > c.reltuples * s.scale_factor + s.threshold) triggers
FROM pg_class c INNER JOIN pg_stat_user_tables t ON t.relname = c.relname,
     settings s 
WHERE t.relname = 'mytable'
```

| n\_dead\_tup | triggers\_at | triggers |
|:-------------|:-------------|:---------|
| 0            | 200050       | false    |


### Start on insert

These parameters control when autovacuum starts on insert :
- autovacuum_vacuum_insert_threshold : minimum number of inserted tuples - default : 1000
- autovacuum_vacuum_insert_scale_factor :  fraction of the table size - default is 0.2 (20% of table size).

```postgresql
WITH settings AS (
  SELECT 
       current_setting('autovacuum_vacuum_insert_threshold')::INT threshold,
       current_setting('autovacuum_vacuum_insert_scale_factor')::DECIMAL scale_factor
)
SELECT 
    t.n_ins_since_vacuum,
    c.reltuples * s.scale_factor + s.threshold triggers_at,
    (t.n_dead_tup::DECIMAL > c.reltuples * s.scale_factor + s.threshold) triggers
FROM pg_class c INNER JOIN pg_stat_user_tables t ON t.relname = c.relname,
     settings s 
WHERE t.relname = 'mytable'
```

| n\_ins\_since\_vacuum | triggers\_at | triggers |
|:----------------------|:-------------|:---------|
| 1000000               | 201000       | false    |

[Reference](https://www.postgresql.org/docs/current/routine-vacuuming.html)

## Storage overhead 

How much space is used for actual data ?
What is the storage overhead ? We saw there is much overhead for an empty block.
Now, what is this overhead for a whole table ?

```postgresql
DROP TABLE IF EXISTS mytable ;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
```

Let's insert rows
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

We have 10 millions rows, one integer for each row (4 bytes) 
```postgresql
SELECT 
    pg_size_pretty(10_000_000 * 4::BIGINT)
```
38 MB, much less than 346 MB

If we check how many rows per block
```postgresql
SELECT
    MAX((ctid::text::point)[1] )
FROM mytable
WHERE (ctid::text::point)[0] = 0
```
226

What is the size of each row ? 
```postgresql
SELECT 
    pg_size_pretty( 8 * 1024 / 226 ::BIGINT)     row_size_block,
    4                                            data_size, 
    pg_size_pretty( 8 * 1024 / 226 ::BIGINT - 4) row_overhead
```
36 bytes, whereas the only field is 4 bytes


If we look at the doc, we find:
- each block has 
  - a header, 24 bytes
  - an array of pointers, 4 bytes each
  - free space, which does not exist here
  - items (rows), for each
    - a header, 23 bytes
    - actual data

Here, we have
```postgresql
SELECT 
    24                      block_header,
    4 * 226                 item_pointer,
    (23 + 4)                item,
    4 * 226                 items_no_header,
    (23 + 4) * 226          items,
    24 + 226 * (4 + 23 + 4) total,
    8 * 1024                block
```
| block\_header | item\_pointer | item | items | total | block |
|:--------------|:--------------|:-----|:------|:------|:------|
| 24            | 904           | 27   | 6102  | 7030  | 8192  |

This is a rough figure (there is some wasted space because of memory alignment).
But we get the idea : in table with few column, metadata takes most of the space.

How much data in table ?
```postgresql
SELECT TRUNC(904 / 8192 ::NUMERIC * 100) || ' %'
```
11 %

[Source](https://www.postgresql.org/docs/current/storage-page-layout.html)


If we create a table with
- 1 integer - 4 bytes
- 1 text, 10 characters UTF-8 - 10 bytes to 40 bytes
- 1 timestamp - 4 bytes

This is from 18 to 44 bytes per row

```postgresql
DROP TABLE IF EXISTS people ;

CREATE TABLE people (
    id  integer,
    name text,
    born_on timestamptz
) WITH (AUTOVACUUM_ENABLED = FALSE);

INSERT INTO people (id, name, born_on)
SELECT n, repeat(left(n::text,1), 10), now() - n * INTERVAL '1 SECOND'::INTERVAL
FROM generate_series(1, 300) AS n;

SELECT *
FROM people;

ANALYZE VERBOSE people;

SELECT relpages block_count
FROM pg_class WHERE relname = 'people';
```

How many rows per block?
```postgresql
SELECT
    MAX((ctid::text::point)[1] )
FROM people
WHERE (ctid::text::point)[0] = 0
```
157

Here, with 25 bytes row, we have this
```postgresql
WITH row AS (
  SELECT  
    157 AS count,
    25  AS size
  )
SELECT 
    24                                   block_header,   
    4 * row.count                        item_pointer,
    (23 + row.size)                      item,
    (23 + row.size) * row.count          items,
    row.size * row.count                 items_no_header,
    24 + row.count * (4 + 23 + row.size) total,
    8 * 1024                             block
FROM row
```
| block\_header | item\_pointer | item | items | items\_no\_header | total | block |
|:--------------|:--------------|:-----|:------|:------------------|:------|:------|
| 24            | 628           | 48   | 7536  | 3925              | 8188  | 8192  |


How much data in table ?
```postgresql
SELECT TRUNC(3925 / 8192 ::NUMERIC * 100) || ' %'
```
47 %




## random or sequential access

### heap or index ?

Heap allow sequential access, indexes allow indexed access.

Random access refers to accessing successively different physical location on a device.
If the device is RAM, or solid-state drive, the overall cost is the unit cost * access count.
If the device is a hard-disk drive, the overall cost may be less if all data is stored: 
- on contiguous blocks in the same platter;
- if the platter are read successively by the arm.

However:
- OS does not allocate space contiguously;
- space is reused by PostgreSQL in the same table.

That means that even if you read a whole table, you may not read data sequentially on disk, so the access can be random. 

If you need some data (filter using a criteria):
- usually, you have to read all the table
- unless you need a few records only (TOP-N, reporting) - but you may end up reading the whole table if you don't find one
- unless you know there is one record only (it is unique) - but you may end up reading the whole table if you don't find one
- unless you have its physical location( `ctid`) - but such location changes frequently

Algorithmic complexity 
- linear search : O(N)
- b-tree : O(log(n))

[index, random, sequential terminology](https://stackoverflow.com/questions/42598716/difference-between-indexed-based-random-access-and-sequential-access)


### Is file contiguous of fs ?

Find its physical location
```postgresql
SELECT pg_relation_filepath('mytable')
FROM pg_settings WHERE name = 'data_directory';
```
base/5/16392

Get the volume 

Check `Mountpoint`
```shell
docker inspect sandbox_postgresql_data;
```

On Linux, it is `/var/lib/docker/volumes/sandbox_postgresql_data/_data/base/16384/16385`

Then run on host
```shell
sudo hdparm --fibmap  /var/lib/docker/volumes/sandbox_postgresql_data/_data/base/16384/16385
```

You'll get the block span
```text
 filesystem blocksize 4096, begins at LBA 0; assuming 512 byte sectors.
 byte_offset  begin_LBA    end_LBA    sectors
           0  526071904  526071919         16
        8192  755184728  755233863      49136
    25165824  692322304  692355071      32768
(..)
```