# Stream-Table Joins: Stream events must be timestamped after the Table records

## Objective

With stream-table join, your table messages *must* already exist (and must be timestamped) before the stream messages. If you re-emit your source stream messages, after the table topic is populated, the join will succeed. See Resources section below for more examples.

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

## Resources
https://rmoff.net/2018/05/17/stream-table-joins-in-ksql-stream-events-must-be-timestamped-after-the-table-messages/
https://stackoverflow.com/questions/50371518/kafka-ksql-simple-join-does-not-work/50390022#50390022
https://docs.ksqldb.io/en/latest/developer-guide/joins/join-streams-and-tables/
