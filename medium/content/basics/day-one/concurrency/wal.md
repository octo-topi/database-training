# WAL

Add many rows: 10 million (last 4 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10000000) AS n;
```

What's table size ?
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size
```
346 MB

You get a lot of writes, which is expected.
But why 1GB, more than table size ?
Because, at least, of WAL files.
```text
Size(R - W)
0,0k - 3,8M
14,0M - 1,3G
156,0k - 20,8M
```

Check WAL files size
```shell
just storage
du --human $PGDATA/pg_wal
```

640 Mb
```text
641M	/var/lib/postgresql/data/pg_wal
```

```postgresql
SHOW full_page_writes;
SHOW wal_log_hints;
```
Setting hint bits does not generate WAL files, unless `wal_log_hints=on`; 
[Source](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-WAL-LOG-HINTS)

Why is it 640 Mb instead of table size, 346 Mb ?
[Source](https://fluca1978.github.io/2021/07/15/PostgreSQLWalTraffic2.html)


If you `CHECKPOINT` and insert again, WAL files do not grow
root@cc1c742e9a47:/var/lib/postgresql/data# du --human $PGDATA/pg_wal
4.0K	/var/lib/postgresql/data/pg_wal/archive_status
4.0K	/var/lib/postgresql/data/pg_wal/summaries
641M	/var/lib/postgresql/data/pg_wal
But if you do not checkpoint, WAL files grow till `max_wil_files`
root@cc1c742e9a47:/var/lib/postgresql/data# du --human $PGDATA/pg_wal
4.0K	/var/lib/postgresql/data/pg_wal/archive_status
4.0K	/var/lib/postgresql/data/pg_wal/summaries
1.3G	/var/lib/postgresql/data/pg_wal



Get WAL size
```postgresql
SELECT
    pg_size_pretty(wal_files.count * s.setting::INT) wal_size
FROM
    (SELECT COUNT(*) AS count FROM pg_ls_dir('pg_wal') WHERE pg_ls_dir ~ '^[0-9A-F]{24}' ) wal_files,
    pg_settings s
WHERE 1=1
    AND s.name = 'wal_segment_size'
;
```
1232 MB