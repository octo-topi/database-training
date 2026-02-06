# On data change

We saw that read queries may be faster with an index.
But what about write queries ?

## Operations

A single query may perform different actions, because of MVCC.

| query    | locate row | modify all columns | implementation - heap    | implementation - index |
|:---------|:-----------|:-------------------|:-------------------------|:-----------------------|
| INSERT   | no         | yes                | add                      | (split), add           |
| DELETE   | yes        | yes                | locate, suppress         |                        |
| UPDATE   | yes        | no (ORM?)          | locate, suppress, insert | (split), add           |
| TRUNCATE | no         | yes                | drop                     | drop                   | 

## Impact of indexes

Indexes have negative and positive impacts. 
Anyway, most of the time, you will use a primary key on the table which will create its own index - which will slow down INSERT anyway.
Therefore, if you need to load a huge amount of data, drop the primary key, load data, and recreate the primary key.  

### Positive 

All queries which have to locate rows (DELETE, UPDATE) may be slower without indexes :
- if the heap scan take most of the time ;
- if the index would be very selective.

### Negative

All queries which have to insert rows (INSERT, UPDATE) may be slower with indexes - if the indexes update take time:
- if there is many indexes on the table;
- in UPDATE, if the column which is updated is indexed (or included in the index).