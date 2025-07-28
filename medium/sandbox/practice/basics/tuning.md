# Tuning

Execution plan = Implementation (execution) of a query

## Storage

Storage, aka Data Structures
- heap-organized table
- partitioned table
- index-organized table

Access structure : Indexes, materialized view (redundancy)
Logical VS physical read (no cache)

## Accessing

What is an access path ?
A technique used by :
- a query (step)
- to retrieve rows from a data structure
- fulfilling the operator (applying a predicate)

Query predicate
> A predicate is an expression that evaluates to TRUE, FALSE (or UNKNOWN).
> Predicates are used in :
>  - the search condition of WHERE clauses and HAVING clauses;
>  - the join conditions of FROM clauses;
>  - (and other constructs where a Boolean value is required).

[SQl server manual](https://learn.microsoft.com/en-us/sql/t-sql/queries/search-condition-transact-sql?view=sql-server-ver17)

Predicate are applied during
- access
- filter

TOP
> Although an access predicate is used to locate rows by taking advantage of an efficient access structure (for example, a hash table in memory, like for operation 2, or an index, like for operation 4), a filter predicate is applied only after the rows have already been extracted from the structure storing them


TOP
>  The selectivity is a value between 0 and 1 representing the fraction of rows filtered by an operation.
> selectivity: rows returned / rows total - strong/weak [0;1]
> cardinality (operation) = selectivity * num_rows = rows returned

You can access data :
- directly (heap) and filter afterward
- indirectly (index) and filter on the flow

## execution plan

Nodes
- postgresql
- oracle

Show the mapping between both

## cause of inefficient access paths

> There are several main causes of inefficient access paths:
> - no suitable access structures (for example, indexes) are available.
> - a suitable access structure is available, but the syntax of the SQL statement doesn’t allow the query optimizer to use it.
> - the table or the index is partitioned, but no pruning is possible. As a result, all partitions are accessed.
> - the table or the index, or both, aren’t suitably partitioned.
> - when the query optimizer makes wrong estimations because of a lack of object statistics, object statistics that aren’t up-to-date, or a wrong query optimizer configuration is in place.
