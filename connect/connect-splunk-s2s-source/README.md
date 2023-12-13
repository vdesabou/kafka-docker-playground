# Splunk S2S Source connector


## Objective

Quickly test [Splunk S2S Source](https://docs.confluent.io/kafka-connect-splunk-s2s/current/index.html#quick-start) connector.


## How to run

Simply run:

```
$ playground run -f splunk-s2s-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

## Details of what the script is doing

Creating Splunk S2S source connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.splunk.s2s.SplunkS2SSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "splunk-s2s-events",
               "splunk.collector.index.default": "default-index",
               "splunk.s2s.port": "9997",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/splunk-s2s-source/config | jq .
```

```bash
echo "log event 1" > splunk-s2s-test.log
echo "log event 2" >> splunk-s2s-test.log
echo "log event 3" >> splunk-s2s-test.log
```

Copy the splunk-s2s-test.log file to the Splunk UF Docker container:

```bash
docker cp splunk-s2s-test.log splunk-uf:/opt/splunkforwarder/splunk-s2s-test.log
```

Configure the UF to monitor the splunk-s2s-test.log file:

```bash
docker exec -i splunk-uf sudo ./bin/splunk add monitor -source /opt/splunkforwarder/splunk-s2s-test.log -auth admin:password
```

Configure the UF to connect to Splunk S2S Source connector:

```bash
docker exec -i splunk-uf sudo ./bin/splunk add forward-server connect:9997
```

Verifying topic `splunk-s2s-events`:

```bash
docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic splunk-s2s-events --from-beginning | grep "log event"
```

Results:

```json
{"event":"log event 1","time":1625495323,"host":"splunk-uf","source":"/opt/splunkforwarder/splunk-s2s-test.log","index":"default","sourcetype":"splunk-s2s-test-too_small"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
