## Overview

## MVCC

Transaction shall be separated from each other; at the very least, they should not see the change other transactions have made but not committed. That's the meaning of "Read commited" isolation level", the default setting in PostgreSQL.

When a query :
- insert some data (INSERT), it is written immediately; on COMMIT it become visible;
- delete some data (DELETE), nothing happens; on COMMIT it become invisible;
- modify some data (UPDATE), a new version is inserted; on COMMIT it become visible and the previous version become invisible.

By the way, an UPDATE is therefore the same as a DELETE followed by an INSERT.

PostgreSQL therefore store all versions of the rows, not the last version (as in Oracle)

PostgreSQL basically compute the visibility for each row on-the-fly. It uses the identifier of the transaction which created or modified the version, which is stored in the version itself. As it is costly, many optimization exists, so the first read on a version will trigger some write.

When a row version is not visible to any active transaction, the space in the block can be reused.
That's what we saw in the storage section, using `VACUUM`.

## Vocabulary

row version

visibility map

xid (also xact, txid) : transaction identifier

xmin, xmax

all-visible

hint bits