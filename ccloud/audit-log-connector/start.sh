#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS=${AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS:-$1}
AUDIT_LOG_CLUSTER_API_KEY=${AUDIT_LOG_CLUSTER_API_KEY:-$2}
AUDIT_LOG_CLUSTER_API_SECRET=${AUDIT_LOG_CLUSTER_API_SECRET:-$3}

if [ -z "$AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS" ]
then
     logerror "AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AUDIT_LOG_CLUSTER_API_KEY" ]
then
     logerror "AUDIT_LOG_CLUSTER_API_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AUDIT_LOG_CLUSTER_API_SECRET" ]
then
     logerror "AUDIT_LOG_CLUSTER_API_SECRET is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# generate data file for externalizing secrets
sed -e "s|:AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS:|$AUDIT_LOG_CLUSTER_BOOTSTRAP_SERVERS|g" \
    -e "s|:AUDIT_LOG_CLUSTER_API_KEY:|$AUDIT_LOG_CLUSTER_API_KEY|g" \
    -e "s|:AUDIT_LOG_CLUSTER_API_SECRET:|$AUDIT_LOG_CLUSTER_API_SECRET|g" \
    ../../ccloud/audit-log-connector/data_audit_cluster.template > ../../ccloud/audit-log-connector/data_audit_cluster

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector reading confluent-audit-log-events from the audit log cluster"
playground connector create-or-update --connector filestream-sink << EOF
{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
               "topics": "confluent-audit-log-events",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "consumer.override.bootstrap.servers": "\${file:/data_audit_cluster:bootstrap.servers}",
               "consumer.override.sasl.mechanism": "PLAIN",
               "consumer.override.security.protocol": "SASL_SSL",
               "consumer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data_audit_cluster:sasl.username}\" password=\"\${file:/data_audit_cluster:sasl.password}\";",
               "consumer.override.client.dns.lookup": "use_all_dns_ips",
               "consumer.override.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
               "consumer.override.confluent.monitoring.interceptor.bootstrap.servers": "\${file:/data:bootstrap.servers}",
               "consumer.override.confluent.monitoring.interceptor.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
               "consumer.override.confluent.monitoring.interceptor.sasl.mechanism": "PLAIN",
               "consumer.override.confluent.monitoring.interceptor.security.protocol": "SASL_SSL"
          }
EOF

sleep 10

log "Verify we have received the data in file"
docker exec -i connect tail -1 /tmp/output.json > /tmp/results.log 2>&1
if [ -s /tmp/results.log ]
then
     log "File is not empty"
     cat /tmp/results.log
else
     logerror "File is empty"
     exit 1
fi
