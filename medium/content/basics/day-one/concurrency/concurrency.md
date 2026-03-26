# concurrency

## overview

Concurrency is not only about isolation levels, lock are another feature.

TOOD: Add ACID properties.

## locks

### theory

In "Read commited" isolation level

If a query is reading a table: 
- can another query insert data in this table without waiting for the read to complete (or trx ?)? Yes
- can another query delete data in this table without waiting ? Only the data which is not read by the reading query. The data which is read cannot be deleted immediately, because of what ?
- can another query update data in this table without waiting ? Same as delete
- can a query which add a column be executed without waiting ?
- can a query which remove a column be executed without waiting ?

In PostgreSQL
- writer don't block reader
- reader don't block writer

### find out locks

[A blog entry](https://blog.octo.com/7-things-a-developer-should-know-about-databases)