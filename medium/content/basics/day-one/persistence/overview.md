# Overview

## Storage
PostgreSQL use heap storage and row storage.
Each table is stored in a single file, and the row is stored contiguously in this file.
The file is a collection of 8Kb records, named blocks. If the file should grow, it will grow block by block. 
Heap is optimized for writing, as it does not sort data. 
It is not optimized for searching, as access is sequential.

## Reuse
When rows are deleted, PostgreSQL does not give back the space to the operating system.
It will reuse it for future insertions. But to do so, a maintenance operation should be run, named `VACUUM`.
It can be performed manually or automatically. 
There are default settings, which you can change if the automatic operation is triggered too often or too few.
If you actually want to give back this space to OS, use `VACUUM FULL` or `TRUNCATE TABLE` if you don't need any rows.


## Statistics

Some statistics are available on table :
- size : `pg_table_size($TABLE)` ;
- usage (how many insert, update, delete) : `pg_stat_user_tables.n_tup_ins, n_tup_del, n_tup_upd` .

Some statistics should be updated by `ANALYZE`:
- size (DB blocks) : `pg_class.relpages` ;
- space usage: `pg_stat_user_tables.n_live_tup, n_dead_tup` 


Usage statistics can be reset using `pg_stat_reset_single_table_counters($TABLE)`.

Free space is not accessible through any views, so you can:
- use [a dedicated query](https://github.com/pgexperts/pgx_scripts/blob/master/bloat/table_bloat_check.sql);
- use `pgstattuple` extension.

## Vocabulary

Block, page

Row, tuple

Bloat

Live and dead tuples