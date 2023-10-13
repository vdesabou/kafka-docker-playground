# Select from Materialized table by composite pkey=struct(one attribute is null)

## Objective

Select from materialized table (contains group by) by STRUCT composite primary key (that has 3 attributes inside) when struct(one attribute is null)

To add a WHERE clause on the composite key, you will need to add each field in your where clause and use the `->` syntax.
For example:
```
SELECT * FROM TRANSACTIONS
WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->PRODUCT_ID IS NULL and TRANSACTION->TXN_ID=500007
EMIT CHANGES LIMIT 1;
```

## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Resources
https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-table/
