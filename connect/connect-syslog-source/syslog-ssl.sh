#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Copying certs to container"
docker cp example.key.pem connect:/
docker cp example.crt.pem connect:/

log "Creating Syslog Source connector"
playground connector create-or-update --connector syslog-source << EOF
{
               "tasks.max": "1",
                    "connector.class": "io.confluent.connect.syslog.SyslogSourceConnector",
                    "syslog.port": "5454",
                    "syslog.listener": "TCPSSL",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "syslog.ssl.key.path": "/example.key.pem",
                    "syslog.ssl.cert.chain.path": "/example.crt.pem"
          }
EOF


sleep 10

log "Test with sample syslog-formatted message sent via netcat"
echo "<34>1 2003-10-11T22:14:15.003Z mymachine.example.com su - ID47 - Your refrigerator is running" | docker run -i --rm --network=host itsthenetwork/alpine-ncat --ssl -v localhost 5454

sleep 5

log "Verify we have received the data in syslog topic"
playground topic consume --topic syslog --min-expected-messages 1 --timeout 60
