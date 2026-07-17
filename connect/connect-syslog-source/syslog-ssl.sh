#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.5.11"
then
     logwarn "minimal supported connector version is 1.5.12 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi




# Syslog source with SSL is not compatible with CFK (Confluent for Kubernetes)
# The test uses docker run --network=host to send syslog messages to localhost:5454,
# but in CFK, the Connect container runs in Kubernetes (not on host Docker network).
# The syslog listener is inside a K8s pod and unreachable from the host.
if [[ "$PLAYGROUND_ENVIRONMENT" == "cfk" ]]
then
  logwarn "⚠️  Syslog source SSL example is not compatible with CFK (Confluent for Kubernetes)"
  logwarn "   Test uses docker run --network=host to send messages to localhost:5454"
  logwarn "   In CFK, Connect runs in Kubernetes pods, not on the host Docker network"
  logwarn "   This example is for Docker Compose environments only"
  exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Copying certs to container"
playground container cp --source example.key.pem --destination connect:/tmp/example.key.pem
playground container cp --source example.crt.pem --destination connect:/tmp/example.crt.pem

log "Creating Syslog Source connector"
playground connector create-or-update --connector syslog-source  << EOF
{
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.syslog.SyslogSourceConnector",
     "syslog.port": "5454",
     "syslog.listener": "TCPSSL",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "syslog.ssl.key.path": "/tmp/example.key.pem",
     "syslog.ssl.cert.chain.path": "/tmp/example.crt.pem"
}
EOF


sleep 10

log "Test with sample syslog-formatted message sent via netcat"
echo "<34>1 2003-10-11T22:14:15.003Z mymachine.example.com su - ID47 - Your refrigerator is running" | docker run -i --rm --network=host itsthenetwork/alpine-ncat --ssl -v localhost 5454

sleep 5

log "Verify we have received the data in syslog topic"
playground topic consume --topic syslog --min-expected-messages 1 --timeout 60
