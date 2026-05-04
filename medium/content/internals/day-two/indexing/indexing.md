# Indexing

Balanced-tree, with double-linked list, containing pointer to rows.
The pointer is the `ctid` we saw in the block structure, in item pointer.

Index structure is not accessed as easily as heap pages.

### How is an index scan implemented ?

Let's recall how an index can in performed :
- traverse b-tree
  - get the index root block from the cache
  - compare the value to the root's children node upper bounds
  - get the children block from the cache and compare it own children upper bound (2 or 3 times)    
  - fetching the leaf node from the cache
- walk the leaf node 
  - follow the chain to find the first entry
  - if the index is not unique, walk the chain until all entries have been found
- fetch all rows, asking all blocks from the cache

If the rows of the result set are not contiguous (at worst, each is in a different blocks), many blocks will have to be retrieved.
How does the planner get its cost ?

### Correlation

#### Get correlation

The correspondence between row value and the physical location of rows in a table is called correlation.

There is, of course, a statistic for this. 
```postgresql
SELECT correlation
FROM database.pg_catalog.pg_stats
WHERE 1=1
    AND tablename = 'mytable'
    AND attname   = 'id'
```

Perfect correlation, 1, is obtained when rows have been inserted according to this column value (ascending or descending).
```postgresql
TRUNCATE TABLE mytable;

INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 1_000_000) AS n;

ANALYZE VERBOSE mytable;

SELECT correlation
FROM database.pg_catalog.pg_stats
WHERE 1=1
    AND tablename = 'mytable'
    AND attname   = 'id'
;    
```

Worst correlation, 0, is when you can't tell which value you will find in the block's next row.
```postgresql
TRUNCATE TABLE mytable;

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 1_000_000) AS n
ORDER BY random();

SELECT id
FROM mytable;

ANALYZE VERBOSE mytable;
```

We get a pretty bad correlation.
```postgresql
SELECT correlation
FROM database.pg_catalog.pg_stats
WHERE 1=1
    AND tablename = 'mytable'
    AND attname   = 'id'
;    
```
-0.00028947237

#### Re-order rows

You can always re-order rows so you've got perfect correlation... if you rewrite the table.

```postgresql
TRUNCATE TABLE mytable;

INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 1_000_000) AS n
ORDER BY random();

CREATE TABLE mytable_sorted AS 
SELECT id FROM mytable ORDER BY id;

ANALYZE VERBOSE mytable_sorted;
```

We're back to 1
```postgresql
SELECT correlation
FROM database.pg_catalog.pg_stats
WHERE 1=1
    AND tablename = 'mytable'
    AND attname   = 'id'
;    
```

You can even sort the table following the index order with `CLUSTER`.
```postgresql
CREATE INDEX mytable_id ON mytable(id);

CLUSTER mytable USING mytable_id;

ANALYZE VERBOSE mytable;
```

We're back to 1
```postgresql
SELECT correlation
FROM database.pg_catalog.pg_stats
WHERE 1=1
    AND tablename = 'mytable'
    AND attname   = 'id'
;    
```
1

### Limitations

But this is not a really good idea, unless for specific needs:
- clustering a table lock every access ;
- you can't correlate on divergent columns ;
- you can't guarantee that new rows will respect correlation;
- row update and delete will change existing correlation.


## Some pre-requisites for indexes

Index scan may not as expensive as a sequential scan, but it is on a cheap operation as it may first appear.

For an index to be useful, several conditions should be met:
- the cardinality of the table is high;
- the index is highly selective;
- the clustering index is high.

## Visibility

### Nothing in indexes

The caveat is that indexes in PostgreSQL don't have any visibility information on the tuples they reference.

This is made to avoid index maintenance:
- on delete, the index entry is kept;
- on update, the old version is kept (and an entry is inserted for the new entry).

If the index return a pointer, a heap fetch (reading the block) should be done to get the visibility information - discarding any row version that should not be visible to the current transaction. 

The following things could therefore happen when the index search return pointers:
- most pointers lead to dead tuples, wasting the very I/O and CPU they are supposed to reduce;
- all columns required by the query are in the index (covering index), but heap fetches should happen anyway.

### Optimizations

Several optimization on index read :
- when an index pointer lead to a dead tuple, the index entry is marked as dead, it can be reused;
- index-only scan can never happen, except if visibility map show that all rows in the blocks are visible to all transactions;

Several optimization on index maintenance :
- HOT update : if a new version of the row is created, and the value which changed is not part of the index, an internal link is created so the index is left untouched.   


## Costs for the planner

The costs computing is much more difficult than for a sequential scan followed by a filter.

We should compute : 
- the cost of index (b-tree and leaf node); 
- the cost of fetching blocks in heap;
- taking into account the cache (at least !).

PostgreSQL estimates than indexed rows are more susceptible to be found in the cache than in a sequential scan.
There are several reasons for this:
- sequential scan on tables larger that 25% of the cache are not cached;
- index entries may point to the same block (there are many rows in the same block). 

It therefore needs to know if the rows will be in the cache.
It assumes that the bigger the cache, related to the table size, the most probable the rows will be cached. 

PostgreSQL does not know the size of the cache, you should set it up yourself.
As rows may be in the OS cache, you should give it the sum of PostgreSQL and OS cache.
```postgresql
SHOW effective_cache_size
```
375MB

A last factor to be taken, for considering index-only scan, is the visibility.
If statistics show most rows are all-visible, the visibility map will be used to skip heap fetches.
Visibility map if updated by VACUUM, so make sure it runs on a regular basis.
```postgresql
VACUUM VERBOSE  mytable;
SELECT
   relpages        block_count
   ,relallvisible  all_visible_block_count
FROM pg_class
WHERE 1=1
    AND relname = 'mytable'
```

| block\_count | all\_visible\_block\_count |
|:-------------|:---------------------------|
| 8850         | 8850                       |


For a glance on cost calculation, check the resource below.

Reference: PostgreSQL Internals, Part IV - Query execution - Index scans / Regular Index Scans

## Index use space

Index use space, as they are pure redundancy.

```postgresql
TRUNCATE TABLE mytable;

INSERT INTO mytable (id)
SELECT 1
FROM generate_series(1, 1_000_000) AS n;

CREATE INDEX mytable_id ON mytable(id);
```

What's its size ?
```postgresql
SELECT 
  pg_size_pretty(pg_table_size('mytable'))    table_size,
  pg_size_pretty(pg_table_size('mytable_id')) index_size
```

| table\_size | index\_size |
|:------------|:------------|
| 69 MB       | 49 MB       |

The index size is lower than table size because it has no visibility bits.


## Summing it up 

Index can be used only if the selectivity of the query predicate is high.
The planner rely on table statistics to know if this is so, then first check the statistics. 