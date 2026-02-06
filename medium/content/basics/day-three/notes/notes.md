# Notes


## Correctness over performance

> The separation of concerns—what is needed versus how to get it—works remarkably well in SQL, but it is still not perfect. The abstraction reaches its limits when it comes to performance: the author of an SQL statement by definition does not care how the database executes the statement. Consequently, the author is not responsible for slow execution. However, experience proves the opposite; i.e., the author must know a little bit about the database to prevent performance problems.

> It turns out that the only thing developers need to learn is how to index. Database indexing is, in fact, a development task. That is because the most important information for proper indexing is not the storage system configuration or the hardware setup. The most important information for indexing is how the application queries the data. This knowledge—about the access path—is not very accessible to database administrators (DBAs) or external consultants. Quite some time is needed to gather this information through reverse engineering of the application: development, on the other hand, has that information anyway.

> This book covers everything developers need to know about indexes—and nothing more. To be more precise, the book covers the most important index type only: the B-tree index.

## Performance

### There is no such thing as a slow query

> Alice: Would you tell me, please, which way I ought to go from here?
> The Cheshire Cat: That depends a good deal on where you want to get to.
> Alice: I don't much care where.
> The Cheshire Cat: Then it doesn't much matter which way you go.
> Alice: ...So long as I get somewhere.
> The Cheshire Cat: Oh, you're sure to do that, if only you walk long enough.


## SLA, by design

## Execution plan 


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

TOP
> There are several main causes of inefficient access paths:
> - no suitable access structures (for example, indexes) are available.
> - a suitable access structure is available, but the syntax of the SQL statement doesn’t allow the query optimizer to use it.
> - the table or the index is partitioned, but no pruning is possible. As a result, all partitions are accessed.
> - the table or the index, or both, aren’t suitably partitioned.
> - when the query optimizer makes wrong estimations because of a lack of object statistics, object statistics that aren’t up-to-date, or a wrong query optimizer configuration is in place.

