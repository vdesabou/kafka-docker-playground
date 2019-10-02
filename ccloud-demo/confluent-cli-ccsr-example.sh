#!/bin/bash

CONFIG_FILE=~/.ccloud/config

set -eu

./ccloud-generate-env-vars.sh $CONFIG_FILE
source delta_configs/env.delta

# Set topic name
topic_name=test2

# Create topic in Confluent Cloud
echo -e "\n# Create topic $topic_name"
kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" $CONFIG_FILE | tail -1` --command-config $CONFIG_FILE --topic $topic_name --create --replication-factor 3 --partitions 6 2>/dev/null || true

# describe example
kafka-consumer-groups --bootstrap-server `grep "^\s*bootstrap.server" $CONFIG_FILE | tail -1` --command-config $CONFIG_FILE --group simple-stream --describe

# Produce messages
echo -e "\n# Produce messages to $topic_name"
num_messages=10
(for i in `seq 1 $num_messages`; do echo "{\"count\":${i}}" ; done) | \
   confluent local produce $topic_name -- \
                                       --cloud \
                                       --config $CONFIG_FILE \
                                       --value-format avro \
                                       --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"count","type":"int"}]}' \
                                       --property basic.auth.credentials.source=${BASIC_AUTH_CREDENTIALS_SOURCE} \
                                       --property schema.registry.basic.auth.user.info=${SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO} \
                                       --property schema.registry.url=${SCHEMA_REGISTRY_URL}

# Consume messages
echo -e "\n# Consume messages from $topic_name"
confluent local consume $topic_name -- \
                                    --cloud \
                                    --config $CONFIG_FILE \
                                    --value-format avro \
                                    --property basic.auth.credentials.source=${BASIC_AUTH_CREDENTIALS_SOURCE} \
                                    --property schema.registry.basic.auth.user.info=${SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO} \
                                    --property schema.registry.url=${SCHEMA_REGISTRY_URL} \
                                    --from-beginning \
                                    --timeout-ms 10000


# https://docs.confluent.io/current/schema-registry/installation/deployment.html#backup-and-restore

# Backup topic

kafka-console-consumer --bootstrap-server `grep "^\s*bootstrap.server" $CONFIG_FILE | tail -1` --consumer.config $CONFIG_FILE --topic _schemas --from-beginning --property print.key=true --timeout-ms 60000 1> schemas.log

# restore
kafka-console-producer --broker-list `grep "^\s*bootstrap.server" $CONFIG_FILE | tail -1` --producer.config $CONFIG_FILE --topic _schemas_restore --property parse.key=true < schemas.log




