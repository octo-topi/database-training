# Instance 

## Specifications

On a PaaS, you can assign limits on hardware.

Locally, we'll rely on docker to achieve this.

Peek into :
- [environment variables](.envrc)
- [docker compose](docker-compose.yml)
- [PostgreSQL configuration](configuration/postgresql.conf)

Hardware is limited:
- 500 Mb RAM;
- 1 CPU.

Data is persisted in a named volume, `sandbox_postgresql_data`.

Configuration is loaded using an anonymous volume.

## Install instance

Clone repository
```shell
git clone git@github.com:octo-topi/database-training.git 
```

Get into the location
```shell
cd database-training/medium/environments/sandbox
```

Check configuration is properly loaded
```terminaloutput
direnv: loading ~/Documents/Octo/postgresql-performance/medium/environments/sandbox/.envrc
direnv: export +CLIENT_APPLICATION_NAME +CONNECTION_STRING +PGDATABASE +PGHOST +PGPASSWORD +PGPORT +PGUSER +POSTGRESQL_CPU_COUNT +POSTGRESQL_DATABASE_NAME +POSTGRESQL_EXPOSED_PORT +POSTGRESQL_IMAGE_VERSION +POSTGRESQL_INTERNAL_PORT +POSTGRESQL_TOTAL_MEMORY_SIZE +POSTGRESQL_USER_NAME +POSTGRESQL_USER_PASSWORD
```

## Start instance

Start the instance.
```shell
just start-instance
```

Check you can connect using your `psql` client.
```shell
just console
```

## Connect IDE

Get the connection details
```shell
just show-ide-connection 
```

Configure your IDE accordingly

## Check monitoring

Get logs
```shell
just logs
```

Search in log for startup message.
```text
docker logs postgresql 2>&1 | grep ready
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