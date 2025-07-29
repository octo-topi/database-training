# Instance 

## Configure instance

On a PaaS, you can assign limits on hardware.

Locally, we'll rely on docker to achieve this.

Peek into :
- [environment variables](../../../sandbox/.envrc)
- [docker compose](../../../sandbox/docker-compose.yml)
- [PostgreSQL configuration](../../../sandbox/configuration/postgresql.conf)

Hardware is limited:
- 500 Mb RAM;
- 1 CPU.

Data is persisted in a named volume, `sandbox_postgresql_data`.

Configuration is loaded using a volume.

## Start instance

Start the instance.
```shell
just start-instance
```

Check you can connect using your `psql` client.
```shell
just console
```

## Check monitoring

Get logs
```shell
just logs
```

You should see the startup message.
```text
2025-07-29 07:49:51.255 UTC [1] LOG:  database system is ready to accept connections
```

Check CPU and memory allocation.
```shell
just stats
```

```text
CONTAINER ID   NAME         CPU %     MEM USAGE / LIMIT   MEM %     NET I/O           BLOCK I/O    PIDS
33dbbd2b5976   postgresql   7.65%     25.24MiB / 500MiB   5.05%     12.3kB / 3.58kB   0B / 831kB   7
```

Check cache size is actually 128 Mb.
```postgresql
select pg_size_pretty(setting::integer * 8 * 1024::numeric) cache
from pg_settings where name = 'shared_buffers'
```

## Access

Check your can get root access in the container.
```shell
just shell
```

## Drop databases

You can drop all databases if needed.

```shell
just stop-instance
just remove-volume 
```