# More

## WAL in a nutshell

Using write-ahead log, you write in WAL **ahead** of writing in data files.

You trade space for speed :
- data is written in several places, it is redundant, so it takes more space;
- but the WAL files are quicker to write - this way, you can keep dirty data in cache, without writing it on disk immediately.

Any way, you do not compromise integrity.

## WAL vs Data files

WAL files are :
- short-lived
- write once, never read
- reusable
- low volume

It's appropriate to put them on a quick, small filesystem.

Data files are :
- long-lived
- written and read many times
- not reusable
- high volume

It's appropriate to put them on a big, slower filesystem.

If you can't get two different speed filesystem, you should at least get two devices for integrity.

## How much data can you lose, anyway ?

In our sandbox instance, the checkpointer and the background writer were nearly disabled, forcing dirty buffer to be written at late as possible.
It cannot cause data loss, just increase recovery time. We were still writing WAL to disk.

You can lose some data (uncommited changes) if the server or database crashes before the `COMMIT` command has been executed. This is expected in `Read commited` isolation level. On `COMMIT`, the OS is asked to write WAL files to disk and PostgreSQL wait for its completion. 

You can lose some data (last transactions) if you set `synchronous_commit=OFF` and the server or database crashes just after `COMMIT`. 
The `COMMIT` will not wait for wal buffer to be written to disk to return control to the client. WAL will still be written, asynchronously, after maximum `3 * wal_writer_delay`.
 
## What if I don't need any guarantee ?

If you can afford to lose your data, and need performance, consider these two options.

When you create an `UNLOGGED` [table](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-UNLOGGED), no WAL is written on data change. 
If a crash happens, PostgreSQL cannot guarantee data integrity, so it truncate the table on restart. If no crash happens, it behaves like a regular table.

When you create an `TEMPORARY` [table](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-TEMPORARY), no WAL is written on data change and the table in truncated where session ends. As data is visible only to the client for its current transaction, no statistics are collected nor vacuum performed, this is definitely not a regular table. 

## What you shouldn't do at all

If you set `fsync=off`, WAL files are not guaranteed to be written to disk: they may be, or not.
If a crash happens, you really cannot know if you loose the last transactions or corrupt the data file.
And if you can detect the data file were corrupted using checksum, you cannot recover them anyway. 

As the [reference](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-FSYNC) says:
> High quality hardware alone is not a sufficient justification for turning off fsync.