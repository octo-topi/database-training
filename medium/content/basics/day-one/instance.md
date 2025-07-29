# Instance 

## Configure instance

PaaS
- hardware
- usage

Peek into :
- [docker compose](../../../sandbox/docker-compose.yml)
- [PostgreSQL configuration](../../../sandbox/configuration/postgresql.conf)

Hardware is limited:
- 500 Mb RAM
- 1 CPU

Data is persisted in a named volume.

Configuration is loaded using a volume.

## Start instance

Start instance
```shell
just start-instance
```

## Logs

Get logs
```shell
just logs
```
2025-07-29 07:49:51.255 UTC [1] LOG:  database system is ready to accept connections

## Allocation

Check CPU and memory allocation
```shell
just stats
```
CONTAINER ID   NAME         CPU %     MEM USAGE / LIMIT   MEM %     NET I/O           BLOCK I/O    PIDS
33dbbd2b5976   postgresql   7.65%     25.24MiB / 500MiB   5.05%     12.3kB / 3.58kB   0B / 831kB   7

Check cache size is actually 125 Mb
```postgresql
select pg_size_pretty(setting::integer * 8 * 1024::numeric)
from pg_settings where name = 'shared_buffers'
```