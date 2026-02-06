# Resilience

## Create data

Start I/O monitoring
```shell
iostat --human 10 | awk 'BEGIN {print "Size(R - W)"} /$DEVICE/  {print $6  " - " $7}'
```

Add many rows (last 4 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

You get these figures
```text
Size(R - W)
0,0k - 3,8M
14,0M - 1,3G
156,0k - 20,8M
```

What's table size ?
```postgresql
SELECT pg_size_pretty(pg_table_size('mytable'))  table_size
```
346 MB

Why did we write 1GB, more than the table size ?
To know what happened, we need to get the I/O for each PostgreSQL process.

## Get each PG processes I/O

Until now, we only have I/O activity for all processes.
We need to display I/O of some processes, the children of `postgres` process.

Wa can use `iotop` or `pidstat`, both available in `sysstat` package.
```shell
sudo apt install sysstat
```

### iotop

`iotop` version on Ubuntu is 0.6, whereas the [current version is 1.31](https://github.com/Tomas-M/iotop).
```shell
iotop --version
```

The command below use 0.6 version, which does not use the [latest parameters](https://man7.org/linux/man-pages/man8/iotop.8.html).

You run `iotop`:
- display only process whose command start by `postgres: `
- who actually does io `--only`
- output each `--delay` seconds in `--batch` mode (no interactive)

```shell
sudo iotop --only --batch --delay=1 | grep "postgres: "
```
You get
```text
36.70 M/s  294.67 M/s  postgres: user database 172.18.0.1(36188) INSERT
 0.00 B/s 1648.97 K/s  postgres: walwriter
35.55 M/s  283.78 M/s  postgres: user database 172.18.0.1(36188) INSERT
 0.00 B/s    3.58 M/s  postgres: checkpointer
 0.00 B/s    7.65 M/s  postgres: walwriter
35.52 M/s  273.85 M/s  postgres: user database 172.18.0.1(36188) INSERT
 0.00 B/s   12.76 M/s  postgres: walwriter
34.93 M/s  267.93 M/s  postgres: user database 172.18.0.1(36188) INSERT
 0.00 B/s   19.13 K/s  postgres: checkpointer
 0.00 B/s    4.82 M/s  postgres: walwriter
36.94 M/s  292.49 M/s  postgres: user database 172.18.0.1(36188) INSERT
```

### pidtstat


`pidtstat` version on Ubuntu is 12.5.2 whereas the [current version is 12.7.9](https://github.com/sysstat/sysstat/tags).
```shell
pidstat -V
```

The command below use 12.5.2 version, which does not use the [latest parameters](https://man7.org/linux/man-pages/man1/pidstat.1.html).

You ask `pidtstat`:
- to show IO `-d`
- to show full command `-l`
- to refresh each 2 seconds `2`

```shell
sudo pidstat -C "postgres: " -l -d 2
```

You get
```text
Average:      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command
Average:      999     49010      0,00   8830,85      0,00       0  postgres: walwriter 
Average:      999     75537  35438,81 275627,86      0,00       0  postgres: user database 172.18.0.1(36188) INSERT
```


## What happened

We see a process named `wal_writer` is also writing data, apart from the dat file insertion.
Was he writing WAL files ?

Let's check WAL files size
```shell
just storage
du --human $PGDATA/pg_wal
```

You get
```text
641M	/var/lib/postgresql/data/pg_wal
```

640 Mb WAL + 346 Mb data file, we pretty much found the cause: WAL files. 


See slides to understand how it works.

## Access data

Setting hint bits does not generate WAL files, unless `wal_log_hints=on`; 
[Source](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-WAL-LOG-HINTS)

Why is it 640 Mb instead of table size, 346 Mb ?
Because WAL file 
- have their own metadata that add overhead
- contains more than rows: CLOG, checkpoints..

[Source](https://fluca1978.github.io/2021/07/15/PostgreSQLWalTraffic2.html)

## Recycle WAL

As soon as you checkpointed, the WAL files are no longer useful.
You can delete them, or recycle them.

As the checkpointer is disabled on this instance, let's checkpoint manually.
```postgresql
CHECKPOINT
```

Add many rows (last 4 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

Check the WAL size have not grown
```text
root@cc1c742e9a47:/var/lib/postgresql/data# du --human $PGDATA/pg_wal
4.0K	/var/lib/postgresql/data/pg_wal/archive_status
4.0K	/var/lib/postgresql/data/pg_wal/summaries
641M	/var/lib/postgresql/data/pg_wal
```

But if you do not checkpoint, WAL files grow till `max_wal_size`
```postgresql
SHOW max_wal_size
```
4GB

Add many rows (last 4 seconds)
```postgresql
INSERT INTO mytable (id)
SELECT n
FROM generate_series(1, 10_000_000) AS n;
```

Check
```text
root@cc1c742e9a47:/var/lib/postgresql/data# du --human $PGDATA/pg_wal
4.0K	/var/lib/postgresql/data/pg_wal/archive_status
4.0K	/var/lib/postgresql/data/pg_wal/summaries
1.3G	/var/lib/postgresql/data/pg_wal
```
WAL files grown from 641M to 1.3G


You can also get WAL size using `pg_ls_dir`
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

Or better, `pg_ls_waldir`
```postgresql
SELECT pg_size_pretty(SUM(size))
FROM pg_ls_waldir()
```
1232 MB

## Peek into WAL: pg_waldump

```postgresql
DROP TABLE IF EXISTS mytable;

CREATE TABLE mytable (
    id  integer
) WITH (AUTOVACUUM_ENABLED = FALSE);
```

```postgresql
SELECT pg_current_wal_insert_lsn()
```
1/33B3C5E0

Insert data two times
```postgresql
INSERT INTO mytable (id) VALUES (-1)
RETURNING ctid
```

It is in block 0, item 1
(0,1)

```postgresql
SELECT pg_current_wal_insert_lsn()
```
1/33B3C6B0

Access fs to run `pg_waldump` binary
```shell
just wal
```

Get details 
```shell
pg_waldump --path=$PGDATA/pg_wal --start=1/33B3C5E0 --end=1/33B3C6B0
```

You get 3 entries:
- INSERT on offset 1 and 2, which are 2 items
- COMMIT
```text
rmgr: Heap        len (rec/tot):     59/    59, tx:        868, lsn: 1/33B3C5E0, prev 1/33B3C5B8, desc: INSERT+INIT off: 1, flags: 0x00, blkref #0: rel 1663/16384/16438 blk 0
rmgr: Transaction len (rec/tot):     34/    34, tx:        868, lsn: 1/33B3C620, prev 1/33B3C5E0, desc: COMMIT 2026-01-29 14:32:15.855243 UTC
rmgr: Heap        len (rec/tot):     59/    59, tx:        869, lsn: 1/33B3C648, prev 1/33B3C620, desc: INSERT off: 2, flags: 0x00, blkref #0: rel 1663/16384/16438 blk 0
rmgr: Transaction len (rec/tot):     34/    34, tx:        869, lsn: 1/33B3C688, prev 1/33B3C648, desc: COMMIT 2026-01-29 14:40:48.486622 UTC
```

The `rel 1663/16384/16438 blk 0` is our `mytable` table
```postgresql
SELECT pg_relation_filepath('mytable')
```
base/16384/16438

## Crash instance recovery

```postgresql
SELECT
    c.relname,
    COUNT(*) dirty_blocks
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
    AND c.relname NOT LIKE 'pg_%'    
    AND b.isdirty IS TRUE
GROUP BY 
    c.relname
```

There is a dirty block

| relname | dirty\_blocks |
|:--------|:--------------|
| mytable | 1             |


This data has not been written to disk, on data files.

```postgresql
SELECT pg_current_wal_insert_lsn()
```
1/33B56B28

Get the latest WAL recorded
```shell
pg_controldata $PGDATA | grep 'Latest.*location'
```

You get
```text
Latest checkpoint location:           1/33B38F80
Latest checkpoint's REDO location:    1/203C0048
```

Let's crash the instance: 

First, choose a backend client 
```shell
ps -fU postgres
```

These have command `user database 172.18.0.1(47690) idle`, eg. `3368`
```text
UID          PID    PPID  C STIME TTY          TIME CMD
postgres       1       0  0 09:30 ?        00:00:12 postgres -c config_file=/etc/postgresql/postgresql.conf
postgres      27       1  0 09:30 ?        00:00:00 postgres: io worker 1
postgres      28       1  0 09:30 ?        00:00:00 postgres: io worker 2
postgres      29       1  0 09:30 ?        00:00:00 postgres: io worker 0
postgres      30       1  0 09:30 ?        00:00:00 postgres: checkpointer 
postgres      31       1  0 09:30 ?        00:00:00 postgres: background writer 
postgres      33       1  0 09:30 ?        00:00:00 postgres: walwriter 
postgres      34       1  0 09:30 ?        00:00:00 postgres: autovacuum launcher 
postgres      35       1  0 09:30 ?        00:00:00 postgres: logical replication launcher 
postgres    3368       1  0 09:37 ?        00:00:09 postgres: user database 172.18.0.1(47690) idle
postgres   35066       1  0 10:47 ?        00:00:00 postgres: user database 172.18.0.1(54646) idle
postgres  101003       1  0 13:12 ?        00:00:08 postgres: user database 172.18.0.1(46586) idle
postgres  127269       1  0 14:10 ?        00:00:00 postgres: user database 172.18.0.1(57384) idle
postgres  143652       1  0 14:46 ?        00:00:00 postgres: user database 172.18.0.1(33902) idle
postgres  143781       1  0 14:46 ?        00:00:00 postgres: user database 172.18.0.1(55320) idle
```

Kill it
```shell
kill -SIGKILL 3368
```

Get logs
```text
2026-01-29 14:57:17.387 GMT [1] LOG:  client backend (PID 3368) was terminated by signal 9: Killed
2026-01-29 14:57:17.387 GMT [1] DETAIL:  Failed process was running: SHOW TRANSACTION ISOLATION LEVEL
2026-01-29 14:57:17.387 GMT [1] LOG:  terminating any other active server processes
2026-01-29 14:57:17.391 GMT [1] LOG:  all server processes terminated; reinitializing
2026-01-29 14:57:17.410 GMT [148714] LOG:  database system was interrupted; last known up at 2026-01-29 14:13:25 GMT
2026-01-29 14:57:17.458 GMT [148714] LOG:  database system was not properly shut down; automatic recovery in progress
2026-01-29 14:57:17.463 GMT [148714] LOG:  redo starts at 1/203C0048
2026-01-29 14:57:18.258 GMT [148724] FATAL:  the database system is not yet accepting connections
2026-01-29 14:57:18.258 GMT [148724] DETAIL:  Consistent recovery state has not been yet reached.
2026-01-29 14:57:19.221 GMT [148714] LOG:  invalid record length at 1/33B56B28: expected at least 24, got 0
2026-01-29 14:57:19.221 GMT [148714] LOG:  redo done at 1/33B56AF0 system usage: CPU: user: 1.27 s, system: 0.35 s, elapsed: 1.75 s
2026-01-29 14:57:19.226 GMT [148715] LOG:  checkpoint starting: end-of-recovery immediate wait
2026-01-29 14:57:19.267 GMT [148715] LOG:  checkpoint complete: wrote 97 buffers (0.6%), wrote 3 SLRU buffers; 0 WAL file(s) added, 19 removed, 0 recycled; write=0.004 s, sync=0.005 s, total=0.043 s; sync files=46, longest=0.002 s, average=0.001 s; distance=319066 kB, estimate=319066 kB; lsn=1/33B56B28, redo lsn=1/33B56B28
2026-01-29 14:57:19.273 GMT [1] LOG:  database system is ready to accept connections
```

The WAL has been replayed from `1/203C0048` (Latest checkpoint's REDO location) but not to `1/33B56B28`, the last one before crash
```text
2026-01-29 14:57:17.463 GMT [148714] LOG:  redo starts at 1/203C0048
```

Get the latest WAL recorded
```shell
pg_controldata $PGDATA | grep 'Latest.*location'
```

We are back to `1/33B56B28`
```text
Latest checkpoint location:           1/33B56B28
Latest checkpoint's REDO location:    1/33B56B28
```

Are data consistent ?
```postgresql
SELECT ctid, id
FROM mytable
```

Yes !

| ctid    | id |
|:--------|:---|
| \(0,1\) | -1 |
| \(0,2\) | -1 |


Let's check the cache
```postgresql
SELECT
    c.relname,
     b.isdirty,
    COUNT(*) blocks
FROM pg_class c
         INNER JOIN pg_buffercache b ON b.relfilenode = c.relfilenode
         INNER JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
WHERE 1=1
    AND c.relname = 'mytable'
    --AND b.isdirty IS TRUE
GROUP BY 
     b.isdirty,
    c.relname
```

No dirty

| relname | isdirty | blocks |
|:--------|:--------|:-------|
| mytable | false   | 1      |


Reference: PostgreSQL Internals, Part II - Buffer cache and WAL - Write-Ahead Log / Recovery
