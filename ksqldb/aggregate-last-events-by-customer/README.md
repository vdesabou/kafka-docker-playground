# Use Case - Aggregate the last X transactions for each unique customer id

## Objective

Example of use case (fraud reports). We need to aggregate the last 3 transactions by customer ID and join this with customer information. We want to join this to another stream whenever theres a fraud decision to create the message to send to the case management system.

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Resources
https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/aggregate-functions/#topk
https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/#reduce
