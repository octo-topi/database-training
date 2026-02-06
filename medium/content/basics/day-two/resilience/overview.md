# Overview

## In a nutshell

Using write-ahead log, you write in WAL **ahead** of writing in data files. It's a permanent-storage deferred write.
That means datafile are inconsistent most of the time, only the shared buffer (cache) is consistent. 

You trade space for speed :
- data is written in several places, it is redundant, so it takes more space;
- but the WAL files are quicker to write - this way, you can keep dirty data in cache, without writing it on disk immediately.

Any way, you do not compromise integrity.

## WAL vs Data files

WAL files are :
- short-lived
- write once, never read
- written in a sequential manner
- written synchronously
- reusable
- low volume

It's appropriate to put them on a quick, small filesystem.

Data files are :
- long-lived
- written and read many times
- written in a random manner
- written asynchronously
- not reusable
- high volume

It's appropriate to put them on a big, slower filesystem.

If you can't get two different speed filesystem, you should at least get two devices for integrity.
