#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.2"; then
    logwarn "WARN: Tiered storage is only available from Confluent Platform 5.4.0"
    exit 0
fi

DOCKER_COMPOSE_FILE_OVERRIDE=$1
# Starting minio
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d minio
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d create-buckets
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml up -d minio
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml up -d create-buckets
fi

log "Minio UI is accessible at http://127.0.0.1:9000 (AKIAIOSFODNN7EXAMPLE/wJalrXUtnFEMI7K7MDENG8bPxRfiCYEXAMPLEKEY)"

sleep 10

log "Creating bucket in Minio"
docker container restart create-buckets

# Starting all other services now that minio is up and bucket created
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../other/tiered-storage-with-minio/docker-compose.yml up -d
fi

# wait for C3 to be started
../../scripts/wait-for-connect-and-controlcenter.sh -a -b

log "Create topic TieredStorage"
docker exec broker kafka-topics --bootstrap-server 127.0.0.1:9092 --create --topic TieredStorage --partitions 6 --replication-factor 1 --config confluent.tier.enable=true --config confluent.tier.local.hotset.ms=60000 --config retention.ms=86400000

log "Sending messages to topic TieredStorage"
seq -f "This is a message %g" 200000 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic TieredStorage

log "Check for uploaded log segments"
docker container logs broker | grep "Uploaded"

log "Listing objects of bucket minio-tiered-storage in Minio"
docker container restart list-buckets
sleep 3
docker container logs --tail=100 list-buckets

log "Sleep 5 minutes (confluent.tier.local.hotset.ms=60000)"
sleep 300

log "Check for deleted log segments"
docker container logs broker | grep "Found deletable segments"