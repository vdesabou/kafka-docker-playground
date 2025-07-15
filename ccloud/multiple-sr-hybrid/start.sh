#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.4.0"; then
    logwarn "Audit logs is only available from Confluent Platform 5.4.1"
    exit 111
fi

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.yml"

# generate sr.json config
sed -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    ../../ccloud/multiple-sr-hybrid/sr-template.json > ../../ccloud/multiple-sr-hybrid/sr.json

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.yml"

# results a re inconsistent depending on RHEL or DEBIAN
if [[ "$TAG" == *ubi8 ]]  || version_gt $TAG_BASE "5.9.0" #starting from 6.0, all images are ubi8
then
     # RHEL
     docker exec -i --privileged --user root -t webserver  bash -c "yum update && yum install -y nc"
     docker exec -d -t webserver bash -c "bash /tmp/httpd_rhel.sh 1500 /tmp/json/sr.json"
else
     # debian
     docker exec -i --privileged --user root -t webserver  bash -c "apt-get update && apt-get install net-tools"
     docker exec -d -t webserver bash -c "bash /tmp/httpd_debian.sh 1500 /tmp/json/sr.json"
fi

sleep 5

log "Executing curl http://localhost:1500/v1/metadata/schemaRegistryUrls"
curl http://localhost:1500/v1/metadata/schemaRegistryUrls


log "Creating topic my_avro_topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic create --topic my_avro_topic
set -e

log "Sending messages to topic my_avro_topic"
playground topic produce -t my_avro_topic --nb-messages 3 << 'EOF'
{
  "fields": [
    {
      "name": "u_name",
      "type": "string"
    },
    {
      "name": "u_price",
      "type": "float"
    },
    {
      "name": "u_quantity",
      "type": "int"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF
