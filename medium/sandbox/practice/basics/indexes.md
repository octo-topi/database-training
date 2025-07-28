# Indexes

## overview

Node type:
- root
- branch (aka internal)
- leaf

Doubly-linked list

Tree traversal
Locate leaf node(s)
Fetch the row

Index node size

Balanced tree: 
- lower the computational complexity to find an element
- no matter how big the data (log N) 
- whichever the value is

https://en.wikipedia.org/wiki/B-tree

## Indexes in databases

Index limits:
- space usage (redundancy)
- update should be done in two places
- update can trigger and tree re-balancing
- a heap fetch should always be done (but if covering, but if visibility from MVCC)

Primary key benefits from indexes 

Delete operations benefits from indexes

Update benefits from indexes ?
It is essentially a delete + insert

A heap-only access benefits from multi-blocks read (full table scan)

## index updates

### operations

#### adding an entry in the leaf node

find the block (tree traversal)
does the block has free space ?
yes
- find the entry to insert after
- create the entry
- changing left and right link to entry
no 
- split the page
- add entry 

#### splitting a node

same for leaf node or internal node
- create a new node
- link the new node to previous and next
- update previous and next (disk access)
- distribute existing entries between old and new
- add new entry

optimization: find for consecutive identical entries and make them a list

#### increasing tree depth

occurs if all ascending nodes are full
cascading page split, a new root node can be created

### when data is created (on index key)

fillfactor is 90 % by default on b-tree

block allocation is 8 kbytes (many nodes)
- as long as you don't reach the fillfactor, you create an entry leaf node 
- if you reach the fillfactor, you do a page split

### when data is updated (on index key)

if the first indexed column is updated, you may need to add a leaf entry in another block (see data created below)

if the second indexed column is updated, you may need to add a leaf in the same block
as fillfactor is 90 % by default on b-tree, you can add an entry in the leaf node 

### when data is updated (not on index key)

MVCC cause a new entry to be created, even in indexed value has not changed
(any change to rows trigger a new entry creation)

optimisation: HOT update in order not to modify the index
conditions:
- not updating an indexed key
- setting the heap fillfactor to less than 100 % so update can be done in the same block