# Select from Materialized table by composite pkey=struct(one attribute is null)

## Objective

Select from materialized table (contains group by) by STRUCT composite primary key (that has 3 attributes inside) when struct(one attribute is null)

For Push Query: to add a WHERE clause on the composite key, you will need to add each field in your where clause and use the `->` syntax.
For example:
```
SELECT * FROM TRANSACTIONS
WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->PRODUCT_ID IS NULL and TRANSACTION->TXN_ID=500007
EMIT CHANGES LIMIT 1;
```

Please note it will **not** work with Pull Query. With Pull Query, it will fail with `Unsupported expression in WHERE clause`:
```
SELECT * FROM TRANSACTIONS
WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->PRODUCT_ID IS NULL and TRANSACTION->TXN_ID=500007;

Unsupported expression in WHERE clause: (TRANSACTION->PRODUCT_ID IS NULL).  See https://cnfl.io/queries for more info.
Add EMIT CHANGES if you intended to issue a push query.
Pull queries require a WHERE clause that:
 - includes a key equality expression, e.g. `SELECT * FROM X WHERE <key-column> = Y;`.
 - in the case of a multi-column key, is a conjunction of equality expressions that cover all key columns.
 - to support range expressions, e.g.,  SELECT * FROM X WHERE <key-column> < Y;`, range scans need to be enabled by setting ksql.query.pull.range.scan.enabled=true
If more flexible queries are needed, , table scans can be enabled by setting ksql.query.pull.table.scan.enabled=true.
ksql> Exiting ksqlDB.
```

You can set directly a STRUCT() in the key. For example:
```
SELECT * FROM TRANSACTIONS_MV2
WHERE TRANSACTION = STRUCT(CUSTOMER_ID:='123', PRODUCT_ID:='10005', TXN_ID:='500005');
```
However, ksqlDB will **not** support if one the of field of your multi-column key is null as you can't set a null value in this expression.

About the performances:
Querying on your composite key will generate a full scan of your table.

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Resources
https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-table/
