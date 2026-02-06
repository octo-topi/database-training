# Overview

## Index

To access data in a scalable fashion:
- we accept the access time will grow in proportion to the count of elements;
- but not so much that it would grow out of proportion.

Balanced tree + doubly linked list + pointers to rows is the solution.
Its complexity is O(log N), which is much more manageable.

## Index vs Heap

| Index is optimized for read                                   | Heap is optimized for write        |
|:--------------------------------------------------------------|:-----------------------------------|
| takes non-critical space (redundancy)                         | take critical space (source truth) |
| sorted data                                                   | unsorted data                      |
| contains data which is not in heap (data about data)          |                                    |
| insert is slow (b-tree traveral + leaf walk + insert / split) | insert is fast (strenght)          |
| delete would be slow (b-tree traveral + leaf walk + delete)   | delete can be fast                 |
| update would be slow (delete node + create node)              | update can be fast                 |

How can write be so fast on heap ?
- data are stored in blocks (bulk)
- the whole row is written at once, not in separate places
- a block can be written everywhere
- a block contains free space for insert (no slow OS system call) and update (no fragmentation)

The b-tree is sorted:
- and sort is expensive if it should be performed after read ; with index, this could be avoided;
- but this sort is done eagerly, before the read happens, on index entry creation ; read may not happen at all;
- to preserve this order, further operations may happen : e.g. to keep the tree balanced.

Writing in heap involve index maintenance:
- check if an index exists on this table which target/include this operation (`UPDATE client_ref`) ;
- on each index
   - do a tree traversal
   - check if there is free space on the leaf node
   - if not, try to free some space (pointers to dead tuples, by inspecting `lp_dead` bit on pointer or fetching the heap)
   - if still not, do a node split with all existing entries
   - insert the new pointer

##