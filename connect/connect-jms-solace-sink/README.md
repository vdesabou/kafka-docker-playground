# JMS Solace Sink connector

## Objective

Quickly test the [JMS Sink](https://docs.confluent.io/kafka-connectors/jms-sink/current/overview.html) connector with a Solace PubSub+ broker.

## Prerequisites

With CP 8.x, the minimum supported connector version is 2.1.16 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jms-solace-sink.sh
```

Solace UI is available at [127.0.0.1:8080](http://127.0.0.1:8080) (`admin`/`admin`).

## What the script does

1. Downloads `sol-jms-10.6.4.jar` and `commons-lang-2.6.jar` and copies them into the `confluentinc-kafka-connect-jms-sink` plugin `lib` folder.
2. Starts the environment with a Solace PubSub+ container and waits for it to be ready.
3. Produces 10 messages to topic `sink-messages` with `playground topic produce`.
4. Creates queue `connector-quickstart` in the `default` Message VPN with the Solace CLI script [`create_queue_cmd`](create_queue_cmd).
5. Creates the JMS sink connector `jms-solace-sink` (`com.solacesystems.jndi.SolJNDIInitialContextFactory`, `smf://solace:55555`, connection factory `/jms/cf/default`).
6. Verifies that the 10 messages are spooled in queue `connector-quickstart`, using the Solace CLI script [`show_queue_cmd`](show_queue_cmd).

Expected output of `show_queue_cmd`:

```text
Queue Name                   Messages      Spool             Bind Status
Message VPN                   Spooled  Usage(MB)   HWM (MB) Count I E A S R D P
------------------------- ----------- ---------- ---------- ----- -------------
connector-quickstart
default                            10       0.00       0.00     0 U U E N P D N
```

This can also be verified manually in the [Solace UI](http://127.0.0.1:8080).
