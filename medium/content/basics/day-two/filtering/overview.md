# Overview

To estimate the number of rows in a result, without executing the query, we need :
- statistics on input rows : how many of them in the table ?
- selectivity : how much will be kept by the operation ?

Count of output rows = count of input rows * selectivity
cardinality (output) = cardinality (input) * selectivity

E.g. if we filter out 90% of a million-row table
cardinality (output) = 1 000 000 * 0.1 = 100 000 rows

## Vocabulary

predicate

cardinality

selectivity

MCV : most common value

histogram

bucket