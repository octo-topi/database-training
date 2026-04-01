# Practice

## connexion overhead

How can you check if the connexion establishment has a noticeable time to execute a query ?

Hints: psql, `time` os function, `pgbench`.

How can you preserve service level (running queries) while opening as few connections as possible ?

## `work_mem` impact

How can you get the influence of `work_mem` setting  ?

Hints: 
- alter the parameter value and check the strategies differ, e.g. to sort a set of data;
- alter the parameter value and time a memory-consuming query in both situations.
 