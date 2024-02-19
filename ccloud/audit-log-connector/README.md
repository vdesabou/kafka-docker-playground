# Confluent Cloud example of connector getting data from Audit Log cluster

## Objective

Quickly test [FileStream Sink](https://docs.confluent.io/home/connect/filestream_connector.html#filesink-connector) connector, which is getting data from Audit Log cluster

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2` for aws, `westeurope`for azure and `europe-west2` for gcp)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `txxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `txxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS> <AUDIT_LOG_CLUSTER_API_KEY> <AUDIT_LOG_CLUSTER_API_SECRET>
```

Note: you can also export these values as environment variable

## Details of what the script is doing

Creating FileStream Sink connector reading confluent-audit-log-events from the audit log cluster:

```bash
playground connector create-or-update --connector filestream-sink  << EOF
{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
               "topics": "confluent-audit-log-events",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "consumer.override.bootstrap.servers": "${file:/data_audit_cluster:bootstrap.servers}",
               "consumer.override.sasl.mechanism": "PLAIN",
               "consumer.override.security.protocol": "SASL_SSL",
               "consumer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data_audit_cluster:sasl.username}\" password=\"\${file:/data_audit_cluster:sasl.password}\";",
               "consumer.override.client.dns.lookup": "use_all_dns_ips",
               "consumer.override.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
               "consumer.override.confluent.monitoring.interceptor.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "consumer.override.confluent.monitoring.interceptor.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
               "consumer.override.confluent.monitoring.interceptor.sasl.mechanism": "PLAIN",
               "consumer.override.confluent.monitoring.interceptor.security.protocol": "SASL_SSL"
          }
EOF
```

The trick is to use consumer override to bootstrap audit log cluster (`data_audit_cluster` file contains parameters for audit log cluster):

```json
     "consumer.override.bootstrap.servers": "${file:/data_audit_cluster:bootstrap.servers}",
     "consumer.override.sasl.mechanism": "PLAIN",
     "consumer.override.security.protocol": "SASL_SSL",
     "consumer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data_audit_cluster:sasl.username}\" password=\"\${file:/data_audit_cluster:sasl.password}\";",
```

Note that we also need to override monitoring interceptors to use the confluent cloud cluster, otherwise it tries to use the audit log cluster  (`data` file contains parameters for confluent cloud cluster):

```json
     "consumer.override.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
     "consumer.override.confluent.monitoring.interceptor.bootstrap.servers": "${file:/data:bootstrap.servers}",
     "consumer.override.confluent.monitoring.interceptor.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
     "consumer.override.confluent.monitoring.interceptor.sasl.mechanism": "PLAIN",
     "consumer.override.confluent.monitoring.interceptor.security.protocol": "SASL_SSL"
```

Verify we have received the data in file:

```bash
docker exec -i connect tail -1 /tmp/output.json > /tmp/results.log 2>&1
if [ -s /tmp/results.log ]
then
     log "File is not empty"
     cat /tmp/results.log
else
     logerror "File is empty"
     exit 1
fi
```

Results:

```json
{datacontenttype=application/json, data={requestMetadata={}, request={correlation_id=-1}, authenticationInfo={principal=User:u-xxx}, authorizationInfo={resourceName=kafka-cluster, patternType=LITERAL, rbacAuthorization={role=OrganizationAdmin, scope={outerScope=[organization=xxx]}}, operation=AccessWithToken, granted=true, resourceType=Cluster}, methodName=mds.Authorize, resourceName=crn://confluent.cloud/organization=xxx/environment=xxx/cloud-cluster=lkc-xxx/kafka=lkc-xxx, serviceName=crn://confluent.cloud/}, subject=crn://confluent.cloud/organization=xxx/environment=xxx/cloud-cluster=lkc-xxx/kafka=lkc-xxx, specversion=1.0, id=xxx, source=crn://confluent.cloud/, time=2022-01-03T09:57:54.547Z, type=io.confluent.kafka.server/authorization}
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
