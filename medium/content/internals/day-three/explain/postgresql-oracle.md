# Explain

If we compare PostgreSQL and Oracle explain plans, several new node appears.
It is interesting to have a look on a different RDBMS on better understand PostgreSQL, let's go.

## Data source

There is two data sources on PostgreSQL:
- heap;
- index.

There are more data sources in Oracle: hash cluster and index-organized table.

Oracle bypass the operating system to access the storage.
It can therefore read many blocks in one pass on a table scan, because it doesn't have to comply with OS buffer size constraints.
This is called multi-block read (MBR).

## Operations

Several operations on data source (index or heap) appears as node in explain plan.
They are also known as access paths: they give you access to data.
After all, "All roads lead to Rome".

In execution plan :
-  PostgreSQL displays one node for (index and/or heap access) together;
-  Oracle displays one node for index access, and one node for heap access.

For an index access :
- PostgreSQl will always display index scan;
- Oracle will distinguish between range or unique.

### Heap

| operation                                                   | Oracle                      | PostgreSQL                   | Notes |
|:------------------------------------------------------------|:----------------------------|------------------------------|-------|
| retrieve a row in heap using a pointer from an index lookup | table access by index rowid | index scan (unique or range) |       |
| retrieve all rows from the heap                             | table access full           | seq scan                     | MBR   | 


### Index

| operation                               | Oracle               | PostgreSQL                         | Notes                                |
|:----------------------------------------|:---------------------|------------------------------------|--------------------------------------|
| b-tree traversal + lead node            | index unique scan    | index-only scan (when heap access) |                                      |
| b-tree traversal + leaf node chain walk | index range scan     | index-only scan (when heap access) |                                      |
| leaf node chain walk, on all leaves     | index full scan      | not implemented                    | needs all rows in index order (sort) |
| read all leaf nodes unsorted on disk    | index fast full scan | not implemented                    | if index is covering, for MBR        |


## Predicate

Filter and access predicate are very different, but PostgreSQl execution plan display them in the same way, which may be confusing.

An access predicate is used to access data: you start reading at a specific location and stop at a specific location.
In PostgreSQL, you can use an access predicate only on an index data source.

A filter predicate is applied on a data you retrieved : you keep it, or discard it.
You can apply a filter predicate on any data source: heap of index.

You can combine 3 predicates to fulfill a query on a single table:
- an access predicate is used for `family_name = 'DOE'` 
- an index filter predicate is used for `first_name = 'Jane'` 
- a table filter predicate is used for `birth_date = '01/01/1900'` 

```postgresql
CREATE INDEX ON people(family_name) INCLUDE(first_name);

SELECT *
FROM people
WHERE family_name = 'DOE' AND first_name = 'Jane' AND birth_date = '01/01/1900';
```

| Structure | Type             | Description                                | Oracle | PostgreSQL  |
|:----------|:-----------------|:-------------------------------------------|:-------|:------------|
| index     | access predicate | leaf node chain walk, start/stop condition | access | index cond. |
|           | filter predicate | leaf node chain walk                       | filter | index cond. |
| table     | filter predicate |                                            | filter | filter      |