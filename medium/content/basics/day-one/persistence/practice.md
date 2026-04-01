# Practice

## Fixed-size types

Create a table with the following columns: 
- one integer;
- one fixed-size text `CHARACTER($LENGTH)`.

Insert data and find:
- the row length;
- how many rows per block.

## Variable-size types

Create another table with variable-size `TEXT` type.

Insert data and find:
- the row length;
- how many rows per block.

## Table content

What is the size of `flights` table ?

How many blocks ? How many rows ?

Get the size of several rows.

## Table usage

Get the table usage : how many rows have been inserted, updated, selected ?

## Follow activity

Generate some activity on the table, not looking at the queries themselves.
```shell
just generate-activity
```

Get its usage again. Which queries have been executed ?

Peek into the database log, can you get the query source ?
```shell
just logs
```

## Track running queries

You know how to get the executed queries, after they've been run.

To see the running queries, you can use several tools:
- `pg_stat_activity` view;
- `pgactivity` tool.

Start `pgactivity` tool
```shell
just pgactivity
```

Generate some activity, can you see the queries ?
```shell
just generate-activity
```

Try again with `pg_stat_activity` view

```shell
just running-queries
```