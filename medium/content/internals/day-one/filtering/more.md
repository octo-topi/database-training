# More

If you want to dive into stats using SQL, use [the array doc](https://www.postgresql.org/docs/current/functions-array.html).

If you want to know more on selectivity, read the [documentation](https://www.postgresql.org/docs/current/row-estimation-examples.html).

## Auto-analyze

Updating statistics too frequently leads to resources hoarding.
Never updating them, whereas data has changed (size or distribution), lead to bad decisions.
So rely on native scheduled analyze, handled by auto-vacuum.

Auto-analyze will be launched by auto-vacuum on two conditions:
- the auto-vacuum has been woken up (even if it did nothing);
- enough data has been modified since last vacuum (manual or scheduled).

This is controlled by 3 parameters :
- autovacuum_naptime : minimum delay between autovacuum - default is one minute
- autovacuum_analyze_threshold : minimum number of inserted, updated or deleted tuples - default : 50 
- autovacuum_analyze_scale_factor : a fraction of the table size to add to autovacuum_analyze_threshold when deciding whether to trigger an ANALYZE - default is 0.1 (10% of table size). 

Let's suppose the auto-vacuum has woken up, will the auto-analyze take place ?
```postgresql
WITH settings AS (
  SELECT 
       current_setting('autovacuum_analyze_threshold')::INT threshold,
       current_setting('autovacuum_analyze_scale_factor')::DECIMAL scale_factor
)
SELECT 
    t.n_mod_since_analyze,
    c.reltuples * s.scale_factor + s.threshold triggers_at,
    (t.n_dead_tup::DECIMAL > c.reltuples * s.scale_factor + s.threshold) triggers
FROM pg_class c INNER JOIN pg_stat_user_tables t ON t.relname = c.relname,
     settings s 
WHERE t.relname = 'mytable'
```
| n\_mod\_since\_analyze | triggers\_at | triggers |
|:-----------------------|:-------------|:---------|
| 0                      | 100050       | false    |

No, it won't run.

Let's update some rows
```postgresql
UPDATE mytable SET id=2 WHERE id BETWEEN 5 AND 200000;
```

| n\_mod\_since\_analyze | triggers\_at | triggers |
|:-----------------------|:-------------|:---------|
| 199996                 | 100050       | true     |

Now it would analyze if started. 

You can change these parameter for your table
```postgresql
ALTER TABLE mytable
SET (autovacuum_analyze_scale_factor = 0.05)
```

[Reference](https://www.postgresql.org/docs/current/routine-vacuuming.html)