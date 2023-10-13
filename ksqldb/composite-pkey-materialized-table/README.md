# Select from Materialized table by composite pkey=struct(one attribute is null)

## Objective

select from materialized table (contains group by) by STRUCT composite primary key (that has 3 attributes inside) when struct(one attribute is null)


## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Resources
https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-table/
