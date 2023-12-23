#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "generate ssh host key"
rm -rf ssh_host*
ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key -P "mypassword"

# needs to be a RSA key
ssh-keygen -p -f ssh_host_rsa_key -m pem -P mypassword -N mypassword -b 2048

RSA_PUBLIC_KEY=$(cat ssh_host_rsa_key.pub)
RSA_PRIVATE_KEY=$(awk '{printf "%s\\r\\n", $0}' ssh_host_rsa_key)

log "RSA_PUBLIC_KEY=$RSA_PUBLIC_KEY"
log "RSA_PRIVATE_KEY=$RSA_PRIVATE_KEY"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ssh-key.yml"

log "Creating SFTP Sink connector"
playground connector create-or-update --connector sftp-sink << EOF
{
               "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "flush.size": "3",
               "schema.compatibility": "NONE",
               "format.class": "io.confluent.connect.sftp.sink.format.csv.CsvFormat",
               "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
               "sftp.host": "sftp-server",
               "sftp.port": "22",
               "sftp.username": "foo",
               "sftp.password": "",
               "tls.private.key": "$RSA_PRIVATE_KEY",
               "tls.public.key": "$RSA_PUBLIC_KEY",
               "tls.passphrase": "mypassword",
               "sftp.working.dir": "/upload",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF


log "Sending messages to topic test_sftp_sink"
playground topic produce -t test_sftp_sink --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

sleep 10

log "Listing content of ./upload/topics/test_sftp_sink/partition\=0/"
docker exec sftp-server bash -c "ls /home/foo/upload/topics/test_sftp_sink/partition\=0/"