# Solution

## connexion overhead 

To estimate the connexion overhead:
- time a query execution in command-line with `time` and `psql`, compare with interactive `psql` with `timing`;
- execute the same query in pgbench with and without `--connect` parameter.

```text
> just execute-query
time --format='Elapsed: %e seconds ' psql --dbname "$CONNECTION_STRING" --command="SELECT SUM(id) FROM mytable LIMIT 1;";
 id 
----
  1
(1 row)

Elapsed: 0.02 seconds 
```

```text
just console
\timing
SELECT SUM(id) FROM mytable LIMIT 1;
\watch 1
Time: 36,497 ms
Time: 30,914 ms
```

To open as few connection as possible, use a connection pool.