## random access

Heap allow sequential access, indexes allow indexed access.

Random access refers to accessing successively different physical location on a device.
If the device is RAM, or solid-state drive, the overall cost is the unit cost * access count.
If the device is a hard-disk drive, the overall cost may be less if all data is stored: 
- on contiguous blocks in the same platter;
- if the platter are read successively by the arm.

However:
- OS does not allocate space contiguously;
- space is reused by PostgreSQL in the same table.

That means that even if you read a whole table, you may not read data sequentially on disk, so the access can be random. 

If you need some data (filter using a criteria):
- usually, you have to read all the table
- unless you need a few records only (TOP-N, reporting) - but you may end up reading the whole table if you don't find one
- unless you know there is one record only (it is unique) - but you may end up reading the whole table if you don't find one
- unless you have its physical location( `ctid`) - but such location changes frequently

Algorithmic complexity 
- linear search : O(N)
- b-tree : O(log(n))

[index, random, sequential terminology](https://stackoverflow.com/questions/42598716/difference-between-indexed-based-random-access-and-sequential-access)


## Is file contiguous ?

Find its physical location
```postgresql
SELECT pg_relation_filepath('mytable')
FROM pg_settings WHERE name = 'data_directory';
```
base/5/16392

Get the volume 

Check `Mountpoint`
```shell
docker inspect sandbox_postgresql_data;
```

On Linux, it is `/var/lib/docker/volumes/sandbox_postgresql_data/_data/base/16384/16385`

Then run on host
```shell
sudo hdparm --fibmap  /var/lib/docker/volumes/sandbox_postgresql_data/_data/base/16384/16385
```

You'll get the block span
```text
 filesystem blocksize 4096, begins at LBA 0; assuming 512 byte sectors.
 byte_offset  begin_LBA    end_LBA    sectors
           0  526071904  526071919         16
        8192  755184728  755233863      49136
    25165824  692322304  692355071      32768
(..)
```
