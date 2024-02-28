# ksqlDB - How to handle NULL value with coalesce

## Objective

See how you can handle null value with coalesce()

Here we will produce the following records:
```
>{"desc":"Global"}
>{"A":{"descA":"GlobalA"}}
>{"A":{"B":{"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
>{"A":{"B":{"C":{"id":"Cid"},"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
>{"A":{"B":{"C":{"id":"Cid","descC":"DESCC"},"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
```
We would like to query the column `descC`. As you can see, this column is not set for the first 4 records.
We will use COALESCE to handle this and return a default value when `descC` is null.

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Resources
https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/#coalesce

## Notes
Pre 0.26 there was a bug in de-referencing -> https://github.com/confluentinc/ksql/issues/7185

