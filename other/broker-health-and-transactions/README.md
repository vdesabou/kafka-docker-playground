# Broker health, failures, rolling restart and transactions

## Objective

Showcase the [`playground broker`](https://kafka-docker-playground.io/#/playground%20broker) commands on 3 brokers: check the health of the cluster, crash and restart a broker, restart all the brokers like a rolling upgrade, read the broker metrics, and find and abort an open transaction that blocks `read_committed` consumers.

🍪 Deep dive: [brokers and transactions](https://kafka-docker-playground.io/#/deep-dive-broker)

## How to run

```bash
playground run -f broker-health-and-transactions<tab>
```

## What the script does

It starts the plaintext environment with 3 brokers (ids 1, 2 and 3, like `--enable-multiple-brokers`), then:

1. describes the cluster (brokers, active controller, feature levels) and checks its health: `broker describe`, `broker health --wait-healthy`
2. creates topic `orders` (3 partitions, replication factor 3, `min.insync.replicas=2`), produces 100 records and displays the key JMX metrics of each broker: `broker metrics --topic orders`
3. kills broker 3, like a crash: `broker stop --broker 3 --kill`. `broker health` exits with 1 and reports broker 3 as down
4. produces 100 more records: acks=all still works with 2 in-sync replicas out of 3
5. starts broker 3 again and waits for the cluster to be healthy: `broker start --broker 3`
6. restarts the 3 brokers one at a time, waiting for a healthy cluster in between: `broker rolling-restart`. The 200 records are still there
7. produces 10 records to topic `payments` in a transaction left open: `topic produce --transactional-id payments-txn --transaction open --transaction-timeout 900000`, then `broker transactions list --state Ongoing`, `describe --transactional-id payments-txn`, `describe-producers --topic payments` (⚠️ on the start offset of the open transaction)
8. produces 5 records without transaction: `topic consume --isolation-level read_committed --count` stays at 0 (read_uncommitted counts them all), because the open transaction holds the last stable offset (LSO)
9. checks that the transaction is not hanging (its coordinator still tracks it, it would be aborted after `transaction.timeout.ms`, 15 minutes here) with `broker transactions find-hanging`, and aborts it anyway: `broker transactions abort --topic payments --partition 0 --start-offset <offset>`. The LSO moves, read_committed now counts the 5 records (the aborted ones are skipped)
10. consumes the 5 records with `--isolation-level read_committed`

## Use it in a repro

While a connector or a client runs:

```bash
# a broker goes away (controlled shutdown, or a crash with --kill), then comes back
playground broker stop --broker 2
playground broker health
playground broker start --broker 2

# a rolling upgrade of the brokers
playground broker rolling-restart

# records in a transaction that never ends (aborted by the coordinator after --transaction-timeout)
playground topic produce -t <topic> --nb-messages 10 --value 'x-%g' --transactional-id my-txn --transaction open --transaction-timeout 900000

# the lag of a read_committed sink is stuck: is a transaction open?
playground broker transactions describe-producers --topic <topic>
playground broker transactions find-hanging --topic <topic>
```
