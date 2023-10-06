# ksqlDB - How to handle empty array or null value within EXPLODE function using CASE

## Objective

See how you can handle empty array or null value within EXPLODE function using CASE.

By design, EXPLODE() does not return a row when working on empty array or null value in the field, when using the function in ksqlDB.

We will see how we can emit the row by using a default value for the field, when original value is empty array or null.

Here we will produce the following records:
```
1 {"field1":"value11","field2":[]}
2 {"field1":"value12","field2":null}
3 {"field1":"value13","field2":[{"field21":"value21","field22":"value22"}]}
```
The column `field2` is an ARRAY of STRUCT. If we use EXPLODE() on `field2`, it will drop records 1 and 2.
So we will use CASE statement to handle empty array and null value in `field2`.

## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Resources
https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/table-functions/#explode
