# Cloud Exporter for Metrics API

# DEPRECATED - Use export endpoint instead

As of December 2021, Confluent recommends using the [export endpoint of the Confluent Cloud Metrics API](https://api.telemetry.confluent.cloud/docs#tag/Version-2/paths/~1v2~1metrics~1{dataset}~1export/get) to extract metrics instead of running a separate service such as the ccloudexporter. This endpoint can be scraped directly with a Prometheus server or other Open Metrics compatible scrapers.
 
## Objective

This demo is using [dabz/ccloudexporter](https://github.com/Dabz/ccloudexporter) in order to pull [Metrics API](https://docs.confluent.io/current/cloud/metrics-api.html) data from Confluent Cloud cluster and be exported to Prometheus.

![CCloud exporter](https://github.com/vdesabou/gifs/raw/master/ccloud/ccloud-demo/ccloudexporter.gif?raw=true)

## Prerequisites

* Properly initialized Confluent Cloud CLI

You must be already logged in with confluent CLI which needs to be setup with correct environment, cluster and api key to use:

Typical commands to run:

```bash
$ confluent login --save

Use environment $ENVIRONMENT_ID:
$ confluent environment use $ENVIRONMENT_ID

Use cluster $CLUSTER_ID:
$ confluent kafka cluster use $CLUSTER_ID

Store api key $API_KEY:
$ confluent api-key store $API_KEY $API_SECRET --resource $CLUSTER_ID --force

Use api key $API_KEY:
$ confluent api-key use $API_KEY --resource $CLUSTER_ID
```

* Create a file `$HOME/.confluent/config`

You should have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```

## How to run

Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

Create topic `ccloudexporter`

```bash
$ create_topic ccloudexporter
```

Create API key and secret with `cloud` resource for Metrics API

```bash
OUTPUT=$(ccloud api-key create --resource cloud)
export API_KEY_CLOUD=$(echo "$OUTPUT" | grep '| API Key' | awk '{print $5;}')
export API_SECRET_CLOUD=$(echo "$OUTPUT" | grep '| Secret' | awk '{print $4;}')
```

Producing data to `ccloudexporter` topic using `kafka-producer-perf-test`:

```bash
$ docker exec tools bash -c "kafka-producer-perf-test --throughput 1000 --num-records 60000 --topic ccloudexporter --record-size 100 --producer.config /tmp/config"
```

Consuming data from `ccloudexporter` topic using `kafka-consumer-perf-test`:

```bash
$ docker exec -e BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS tools bash -c "kafka-consumer-perf-test --messages 60000 --topic ccloudexporter --consumer.config /tmp/config --broker-list $BOOTSTRAP_SERVERS"
```

Grafana is available at http://127.0.0.1:3000 (login/password is `admin`/`admin`)
