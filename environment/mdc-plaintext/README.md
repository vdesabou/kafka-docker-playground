# Multi Data Center PLAINTEXT

## Description

This is a deployment with no security, it has 2 clusters: `europe` and `us`:

For each cluster, we have:

* 1 zookeeper
* 1 broker
* 1 connect


control-center is monitoring the two clusters

N.B: we have dedicated zookepper and broker for metrics.

## 📊 Grafana (`--enable-jmx-grafana`)

`playground run -f <example> --enable-jmx-grafana` (or `playground start-environment --environment mdc-plaintext` with `ENABLE_JMX_GRAFANA=true`) adds the same monitoring stack as the single-cluster environments, for both clusters:

* Grafana: http://127.0.0.1:3000 (admin/password), with the dashboards of `environment/plaintext/grafana/provisioning/dashboards`: pick the cluster with the `env` variable (`europe` or `us`), for example in *Kafka cluster*, *Kafka Connect cluster*, *Cluster Linking* and *Cluster Linking Overview*
* Prometheus: http://127.0.0.1:9090, configured in [`prometheus/prometheus.yml`](prometheus/prometheus.yml): JMX exporter of `broker-europe`, `broker-us`, `controller-europe`, `controller-us`, `connect-europe`, `connect-us` (label `env`)
* Kafka Lag Exporter on both clusters, configured in [`kafka-lag-exporter/application.conf`](kafka-lag-exporter/application.conf): label `cluster_name` `europe` or `us` in the *Kafka Lag Exporter* dashboard
* Pyroscope: http://127.0.0.1:4040

Example, cluster linking metrics while the link of the example replicates:

```bash
playground run -f multi-data-center/cluster-linking/start-plaintext.sh --enable-jmx-grafana
```

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Credits

All credits to @framiere with repository [MDC and single views](https://github.com/framiere/mdc-with-replicator-and-regexrouter)