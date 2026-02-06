# More

## Explore WAL file

If you WAL file is huge, you can get an overall using `--stats` parameter.
```shell
pg_waldump --stats --path=$PGDATA/pg_wal --start=1/33B3C5E0 --end=1/33B3C6B0
```

We see 
- there are 2 entries
- there is much  `Heap/Record`
```text
WAL statistics between 1/33B3C5E0 and 1/33B3C648:
Type                                           N      (%)          Record size      (%)             FPI size      (%)        Combined size      (%)
----                                           -      ---          -----------      ---             --------      ---        -------------      ---
XLOG                                           0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Transaction                                    1 ( 50.00)                   34 ( 36.56)                    0 (  0.00)                   34 ( 36.56)
Storage                                        0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
CLOG                                           0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Database                                       0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Tablespace                                     0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
MultiXact                                      0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
RelMap                                         0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Standby                                        0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Heap2                                          0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Heap                                           1 ( 50.00)                   59 ( 63.44)                    0 (  0.00)                   59 ( 63.44)
Btree                                          0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Hash                                           0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Gin                                            0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Gist                                           0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Sequence                                       0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
SPGist                                         0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
BRIN                                           0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
CommitTs                                       0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
ReplicationOrigin                              0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
Generic                                        0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
LogicalMessage                                 0 (  0.00)                    0 (  0.00)                    0 (  0.00)                    0 (  0.00)
                                        --------                      --------                      --------                      --------
Total                                          2                            93 [100.00%]                   0 [0.00%]                    93 [100%]
```

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