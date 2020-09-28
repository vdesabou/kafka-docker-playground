# Mapr Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-mapr-sink/asciinema.gif?raw=true)

## Objective

Quickly test [Mapr Sink](https://docs.confluent.io/current/connect/kafka-connect-maprdb/index.html#mapr-db-sink-connector-for-cp) connector.

## How to run

**WARNING**: It only works with UBI 8 image, make sure to set environment variable `TAG`:

```bash
export TAG=6.0.0-1-ubi8
```

Simply run:

```
$ ./mapr-sink.sh
```

## Details of what the script is doing

Login with maprlogin on mapr side (mapr)

```bash
$ docker exec -i mapr bash -c "maprlogin password -user mapr" << EOF
mapr
EOF
```

Create table /mapr/maprdemo.mapr.io/maprtopic

```bash
$ docker exec -i mapr bash -c "mapr dbshell" << EOF
create /mapr/maprdemo.mapr.io/maprtopic
EOF
```

Configure Mapr Client

```bash
$ docker exec -i --privileged --user root -t connect bash -c "/opt/mapr/server/configure.sh -secure -N maprdemo.mapr.io -c -C $MAPR_IP:7222 -u appuser -g appuser"
```

```bash
$ docker cp mapr:/opt/mapr/conf/ssl_truststore /tmp/ssl_truststore
$ docker cp /tmp/ssl_truststore connect:/opt/mapr/conf/ssl_truststore
```

Login with maprlogin on client side (connect)

```bash
$ docker exec -i connect bash -c "maprlogin password -user mapr" << EOF
mapr
EOF
```

Sending messages to topic maprtopic

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic maprtopic --property parse.key=true --property key.separator=, << EOF
1,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record1"}}
2,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record2"}}
3,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record3"}}
EOF
```

Creating Mapr sink connector

```bash
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mapr.db.MapRDbSinkConnector",
               "tasks.max": "1",
               "mapr.table.map.maprtopic" : "/mapr/maprdemo.mapr.io/maprtopic",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "topics": "maprtopic"
          }' \
     http://localhost:8083/connectors/mapr-sink/config | jq .
```

Verify data is in Mapr

```bash
docker exec -i mapr bash -c "mapr dbshell" << EOF
find /mapr/maprdemo.mapr.io/maprtopic
EOF
```

Results:

```
====================================================
*                  MapR-DB Shell                   *
* NOTE: This is a shell for JSON table operations. *
====================================================
Version: 6.1.0-mapr

MapR-DB Shell
maprdb mapr:> find /mapr/maprdemo.mapr.io/maprtopic
{"_id":"1","record":"record1"}
{"_id":"2","record":"record2"}
{"_id":"3","record":"record3"}
3 document(s) found.
maprdb mapr:>
```

Mapper UI MCS is running at [https://127.0.0.1:8443](https://127.0.0.1:8443) (`mapr/map`)

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
