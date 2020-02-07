# Splunk Sink connector

![asciinema](asciinema.gif)

## Objective

Quickly test [Splunk Sink](https://docs.confluent.io/current/connect/kafka-connect-solace/sink/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./splunk-sink.sh
```

Splunk UI is available at [127.0.0.1:8000](http://127.0.0.1:8000) `admin/password`

## Details of what the script is doing

Create topic `splunk-qs`

```bash
docker exec broker kafka-topics --create --topic splunk-qs --partitions 10 --replication-factor 1 --zookeeper zookeeper:2181
```

Creating Splunk sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.splunk.kafka.connect.SplunkSinkConnector",
                    "tasks.max": "1",
                    "topics": "splunk-qs",
                    "splunk.indexes": "main",
                    "splunk.hec.uri": "http://splunk:8088",
                    "splunk.hec.token": "99582090-3ac3-4db1-9487-e17b17a05081",
                    "splunk.sourcetypes": "my_sourcetype",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/splunk-sink/config | jq .
```

Note: The token `99582090-3ac3-4db1-9487-e17b17a05081` is coming from `./default.yml`:

```yaml
hec_token: 99582090-3ac3-4db1-9487-e17b17a05081
```

If you want to manually create the token using UI, follow steps from [Quick Start](https://docs.confluent.io/current/connect/kafka-connect-splunk/splunk-sink/index.html#quick-start)

Sending messages to topic splunk-qs

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic splunk-qs << EOF
This is a test with Splunk 1
This is a test with Splunk 2
This is a test with Splunk 3
EOF
```

Verify data is in splunk (`FIXTHIS: it takes around 60 seconds to appear in Splunk`)

```bash
docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk search "source=\"http:splunk_hec_token\"" -auth "admin:password"'
```

Results:

```
This is a test with Splunk 3
This is a test with Splunk 2
This is a test with Splunk 1
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
