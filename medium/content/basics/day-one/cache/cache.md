# Cache

## OS feature reuse

PostgreSQL use most of the features of the OS :
- each connection is handled by an OS process;
- data is shared between processes using shared memory;
- processed are sending signals to each other.

I/O make no difference : PostgreSQL use the OS to access the filesystem and devices.

## Read a file from OS

When a user process want to read a file:
- a system call is made to the OS;
- the OS find all the blocks where the file is located;
- the OS looks into the cache, a zone in memory, for blocks;
- if the blocks are all there, he returns them to the user process;
- if some blocks are missing, the OS reads them from the device:
  - it puts the blocks in cache;
  - he returns them to the user process.

The OS use a cache because some file are frequently used, and I/O is way slower than memory.

## Read a file for PostgreSQL

This is no different for PostgreSQL: all data that should be read from disk should be asked to the OS. We already know that PostgreSQL store all rows of the table in a file, and how to locate it. 
 
Now, a database will have to read a huge amount of data, say for a sequential scan of a table. As it will ask the OS to do it, the OS will use much of its cache for it, although some built-in features prevent a process to use all the cache for himself.

Let's suppose the query use a filter.
```postgresql
SELECT *
FROM mytable
WHERE id = 1
```

Q: Should all data from the table go through the OS cache and returned to the database, even thought only one row is needed ?

We may think it would be enough to filter out all data before returning it to the database, but we saw the storage format of a database block: the row's fields values cannot be read directly, and the visibility rules should be applied. Therefore, there is no filtering. If the file is 1 GB, 1GB will be returned to the database, even though no rows match the query.

## PostgreSQL own cache

PostgreSQL has the same hypothesis as the OS: some data will be used frequently, for example the `user` table, and I/O is slow, so it is better to use a cache. However, he can't rely on the OS cache, as this cache is used by processes other than the database, reading other file that table file. PostgreSQL has its own cache.

The disadvantage of two caches, database and OS, is that a file (at least a block of a file) may exist in both caches, thus "wasting space". There is no way around it, but for PostgreSQL to do direct I/O, reading by himself.

PostgreSQL store its cache in shared memory, which is accessible to all database processes.
The data is stored "as-is", without being decoded. There is no way to find a row of a table in the cache, if it's dead or to get a row value.

## Invalidating the cache

If there is no space left in PostgreSQL cache, which happens most of the time, some blocks should be evicted from the cache. In order to keep the one that are used most often, a usage counter is considered: the block that are evicted first are the less used.

Dirtied.

The real problem comes for writing. If a block is modified, it is modified in the cache



All OS, when dealing with filesystems, use a small unit called block, or page, whose size is usually 4kb.
You can't read or write less than this unit from the OS, even if the block size of the disk is smaller.

PostgreSQL use a 8kb block size, which means that 1 block in database is 2 blocks in OS.

PostgreSQL cannot read or write from disk by himself, he should ask the OS to do so.
He won't even read or write from the disk, but from the OS cache.