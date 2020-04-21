# Syslog Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-syslog-source/asciinema.gif?raw=true)

## Objective

Quickly test [Syslog Source](https://docs.confluent.io/current/connect/kafka-connect-syslog/index.html#quick-start) connector.


## How to run

Simply run:

```
$ ./syslog.sh
```

## Details of what the script is doing

Creating Syslog Source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "io.confluent.connect.syslog.SyslogSourceConnector",
                    "syslog.port": "5454",
                    "syslog.listener": "TCP",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/syslog-source/config | jq .
```

Test with sample syslog-formatted message sent via netcat

```bash
$ <34>1 2003-10-11T22:14:15.003Z mymachine.example.com su - ID47 - Your refrigerator is running" | docker run -i --rm --network=host subfuzion/netcat -v -w 0 localhost 545
```

Verify we have received the data in syslog topic

```bash
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic syslog --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 1
```

Results:

```json
{
    "appName": {
        "string": "su"
    },
    "date": 1065910455003,
    "deviceEventClassId": null,
    "deviceProduct": null,
    "deviceVendor": null,
    "deviceVersion": null,
    "extension": null,
    "facility": {
        "int": 4
    },
    "host": {
        "string": "mymachine.example.com"
    },
    "level": {
        "int": 2
    },
    "message": {
        "string": "Your refrigerator is running"
    },
    "messageId": {
        "string": "ID47"
    },
    "name": null,
    "processId": null,
    "rawMessage": {
        "string": "<34>1 2003-10-11T22:14:15.003Z mymachine.example.com su - ID47 - Your refrigerator is running"
    },
    "remoteAddress": {
        "string": "192.168.208.1"
    },
    "severity": null,
    "structuredData": null,
    "tag": null,
    "type": "RFC5424",
    "version": {
        "int": 1
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
