# Syslog Source connector

## Objective

Quickly test the [Syslog Source](https://docs.confluent.io/kafka-connectors/syslog/current/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 1.5.12 or later.
* `nc` (netcat) on the host for `syslog.sh`.
* `syslog-ssl.sh` is not supported with the `cfk` environment.

## How to run

```bash
playground run -f syslog.sh
```

| Script | Description |
| --- | --- |
| `syslog.sh` | TCP listener (`syslog.listener=TCP`) on port `5454` |
| `syslog-ssl.sh` | TLS listener (`syslog.listener=TCPSSL`) using `example.key.pem` / `example.crt.pem`; the message is sent with `ncat --ssl` |

## What the script does

1. Creates the Syslog Source connector listening on port `5454` (writes to topic `syslog`).
2. Sends a sample syslog-formatted message:

   ```bash
   echo "<34>1 2003-10-11T22:14:15.003Z mymachine.example.com su - ID47 - Your refrigerator is running" | nc -v -w 0 localhost 5454
   ```

3. Verifies the message with `playground topic consume --topic syslog`.
