# Subject

```postgresql
SELECT
 't'
 ,t.id
 ,'table=>'
 ,t.* 
FROM table t
WHERE 1=1
    AND t.id = 8
ORDER BY t.id DESC    
```