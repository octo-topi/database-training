# Overview

Reading from/writing to a device can be several order of magnitude slower that memory.

Because we usually read the same data over and over again, PostgreSQL has its own cache. 

But its entries are :
- read form OS cache;
- written to OS cache.

OS cache is used for read and write and cannot be bypassed.

PostgreSQL cache is vulnerable to crashes: by definition, its content are not written to disk immediately.

A SELECT can trigger writes.