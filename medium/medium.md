# Medium

## Introduction

### Correctness over performance

> The separation of concerns—what is needed versus how to get it—works remarkably well in SQL, but it is still not perfect. The abstraction reaches its limits when it comes to performance: the author of an SQL statement by definition does not care how the database executes the statement. Consequently, the author is not responsible for slow execution. However, experience proves the opposite; i.e., the author must know a little bit about the database to prevent performance problems.

> It turns out that the only thing developers need to learn is how to index. Database indexing is, in fact, a development task. That is because the most important information for proper indexing is not the storage system configuration or the hardware setup. The most important information for indexing is how the application queries the data. This knowledge—about the access path—is not very accessible to database administrators (DBAs) or external consultants. Quite some time is needed to gather this information through reverse engineering of the application: development, on the other hand, has that information anyway.

> This book covers everything developers need to know about indexes—and nothing more. To be more precise, the book covers the most important index type only: the B-tree index.

### Performance

#### There is no such thing as a slow query

> Alice: Would you tell me, please, which way I ought to go from here?
> The Cheshire Cat: That depends a good deal on where you want to get to.
> Alice: I don't much care where.
> The Cheshire Cat: Then it doesn't much matter which way you go.
> Alice: ...So long as I get somewhere.
> The Cheshire Cat: Oh, you're sure to do that, if only you walk long enough.


#### SLA, by design

## Performance

You can't use a database without index, why ?
Because access would be slow, why ?
Because data should be read on fs, which is 10⁵ slower that memory, why ?
Because it can't fit in memory, why ?
Because huge amount of data today

Telephone book metaphor:
- can't use phone most of the time without index
- index takes place in the book
- data cannot be updated without updating index (or it would be useless)

Metaphor limit
- data is stored in heap which is unsorted, whereas phone number are sorted (by location, then first name)
- can't load phone book index in memory (no memory whatsoever), in cache
- you've got bookmarks in books, not in database