# SNMP Trap Source connector

## Objective

Quickly test the [SNMP Trap Source](https://docs.confluent.io/kafka-connectors/snmp/current/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 1.3.3 or later.

## How to run

```bash
playground run -f snmp-trap-source.sh
```

## What the script does

1. Creates the SNMP Trap Source connector listening on `0.0.0.0:10161` with SNMP v3 enabled (user `mysecurityname`, MD5 authentication, DES privacy), writing to topic `snmp-kafka-topic`.
2. Sends an SNMP v3 trap from the `snmptrap` container to `connect:10161`:

   ```bash
   snmptrap -v 3 -c public -u mysecurityname -l authPriv -a MD5 -A myauthpassword -x DES -X myprivacypassword connect:10161 '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 i 123456
   ```

3. Verifies the trap is received with `playground topic consume --topic snmp-kafka-topic`.
