# Confluent Cloud example of connector getting data from Audit Log cluster

## Objective

Quickly test the [FileStream Sink](https://docs.confluent.io/platform/current/connect/filestream_connector.html#filesink-connector) connector, reading data from the Confluent Cloud Audit Log cluster.

A local Connect worker is attached to your Confluent Cloud cluster, and the connector uses consumer overrides to read the `confluent-audit-log-events` topic from the separate audit log cluster.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS` | Bootstrap servers of the audit log cluster |
| `AUDIT_LOG_CLUSTER_API_KEY` | API key for the audit log cluster |
| `AUDIT_LOG_CLUSTER_API_SECRET` | API secret for the audit log cluster |

You can get these values with `confluent audit-log describe` and create an API key for the audit log cluster with the Confluent CLI.

## How to run

```bash
export AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS="<bootstrap servers>"
export AUDIT_LOG_CLUSTER_API_KEY="<api key>"
export AUDIT_LOG_CLUSTER_API_SECRET="<api secret>"
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | FileStream Sink connector reading `confluent-audit-log-events` from the audit log cluster |

## What the script does

1. Generates the `data_audit_cluster` file (from `data_audit_cluster.template`) with the audit log cluster credentials, mounted in the `connect` container to externalize secrets.
2. Starts the `ccloud` environment (local Connect worker connected to Confluent Cloud).
3. Creates the FileStream Sink connector `filestream-sink` on topic `confluent-audit-log-events`, writing to `/tmp/output.json`.
4. Verifies that `/tmp/output.json` in the `connect` container is not empty.

## How it works

The trick is to use consumer overrides to point the connector to the audit log cluster, with credentials read from the `data_audit_cluster` file by the `FileConfigProvider`:

```json
"consumer.override.bootstrap.servers": "${file:/data_audit_cluster:bootstrap.servers}",
"consumer.override.sasl.mechanism": "PLAIN",
"consumer.override.security.protocol": "SASL_SSL",
"consumer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data_audit_cluster:sasl.username}\" password=\"${file:/data_audit_cluster:sasl.password}\";",
"consumer.override.client.dns.lookup": "use_all_dns_ips"
```

Example of record written to the file:

```json
{datacontenttype=application/json, data={requestMetadata={}, request={correlation_id=-1}, authenticationInfo={principal=User:u-xxx}, authorizationInfo={resourceName=kafka-cluster, patternType=LITERAL, rbacAuthorization={role=OrganizationAdmin, scope={outerScope=[organization=xxx]}}, operation=AccessWithToken, granted=true, resourceType=Cluster}, methodName=mds.Authorize, resourceName=crn://confluent.cloud/organization=xxx/environment=xxx/cloud-cluster=lkc-xxx/kafka=lkc-xxx, serviceName=crn://confluent.cloud/}, subject=crn://confluent.cloud/organization=xxx/environment=xxx/cloud-cluster=lkc-xxx/kafka=lkc-xxx, specversion=1.0, id=xxx, source=crn://confluent.cloud/, time=2022-01-03T09:57:54.547Z, type=io.confluent.kafka.server/authorization}
```
