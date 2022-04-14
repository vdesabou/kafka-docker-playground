# Cloud Exporter for Metrics API

# DEPRECATED - Use export endpoint instead

As of December 2021, Confluent recommends using the [export endpoint of the Confluent Cloud Metrics API](https://api.telemetry.confluent.cloud/docs#tag/Version-2/paths/~1v2~1metrics~1{dataset}~1export/get) to extract metrics instead of running a separate service such as the ccloudexporter. This endpoint can be scraped directly with a Prometheus server or other Open Metrics compatible scrapers.
 
## Objective

This demo is using [dabz/ccloudexporter](https://github.com/Dabz/ccloudexporter) in order to pull [Metrics API](https://docs.confluent.io/current/cloud/metrics-api.html) data from Confluent Cloud cluster and be exported to Prometheus.


## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

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
