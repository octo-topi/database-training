## Optimizations

### Setting all_visible in visibility map on VACUUM

Rows that have been inserted in bulk, and never updated, fill whole blocks.
Visibility checks should be performed on hint bits, for each row.

To optimize access for wbole block, a hint bit in the header is written by vacuum.
It is set when all block rows are visible to all transactions.

Let's do ot
````postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
````

Add many rows: 10 million (last 40 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
```

Gather stats
```postgresql
ANALYZE VERBOSE mytable
```

Check that no blocks are now marked as "all rows are visibles to all transactions".
```postgresql
SELECT
    relpages       block_count               -- Number of pages
   ,relallvisible  all_visible_block_count   -- Number of pages that are visible to all transactions
FROM pg_class
WHERE 1=1
    AND relname = 'mytable'
    --AND relpages <> 0
;
```

| block\_count | all\_visible\_block\_count |
|:-------------|:---------------------------|
| 44248        | 0                          |


```postgresql
VACUUM VERBOSE mytable
```

Check that all blocks are now marked as "all rows are visibles to all transactions".
```postgresql
SELECT
   relpages       block_count          
   ,relallvisible  all_visible_block_count 
   ,TRUNC(relallvisible / relpages) * 100 || ' %' pct_visible
FROM pg_class
WHERE 1=1
    AND relname = 'mytable'
    --AND relpages <> 0
;
```

| block\_count | all\_visible\_block\_count | pct\_visible |
|:-------------|:---------------------------|:-------------|
| 44248        | 44248                      | 100 %        |


[Reference](https://www.cybertec-postgresql.com/en/speeding-up-things-with-hint-bits/)

### Mark row version as dead on SELECT

AKA Page pruning.

Now you know that PostgreSQL is optimized for few writes, many read. What if you  update the same row many times ? It will create many versions, and older ones will be discarded quickly. 

That means several things:
- the size of your table will keep growing;
- therefore any sequential scan will take longer;
- unless you do some VACUUM, but VACUUM use resources (CPU and I/O) and cause contention (lock).

What can you do to mitigate that ?
You can use a feature call fillfactor to keep some space in the block for row's update, so that UPDATE create the version in the same block. When a SELECT read a block which does not have enough free space, it checks if the versions in the block are still visible. If not, it marks these versions as dead.

Therefore, an UPDATE with happens afterward on the block can use the space of the dead version to create a new version: you didn't have to trigger a VACUUM on the whole table and you have its benefits.

There is even more: all live versions in blocks are moved to the end, allowing for a single continuous free space at the beginning: no fragmentation.

Need a fill factor < 100% and update rows several times (INSERT doesn't work)

But pointer to tuples are not removed, because they may be referenced by indexes (move this to index section ?)

Reference: PostgreSQL Internals, Part I - Isolation and MVCC / Page pruning
