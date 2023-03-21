#!/bin/sh

. /etc/confluent/docker/bash-config

# Docker workaround: Remove check for KAFKA_ZOOKEEPER_CONNECT parameter
sed -i '/KAFKA_ZOOKEEPER_CONNECT/d' /etc/confluent/docker/configure

# Docker workaround: Ignore cub zk-ready
sed -i 's/cub zk-ready/echo ignore zk-ready/' /etc/confluent/docker/ensure

if [[ $KAFKA_PROCESS_ROLES == "controller" ]]
then
  # Docker workaround: Remove check for KAFKA_ADVERTISED_LISTENERS when process.roles=controller
  sed -i 's/dub ensure KAFKA_ADVERTISED_LISTENERS/echo ignore ensure KAFKA_ADVERTISED_LISTENERS/' /etc/confluent/docker/configure
fi

# KRaft required step: Format the storage directory with a new cluster ID
if [[ -z "${CLUSTER_ID-}" ]]
then
  export CLUSTER_ID
  CLUSTER_ID=$(kafka-storage random-uuid)
fi

echo "kafka-storage format --ignore-formatted --cluster-id $CLUSTER_ID --config /etc/kafka/kafka.properties" >> /etc/confluent/docker/ensure