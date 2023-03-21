#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.kerberos.yml"

# following https://www.confluent.io/blog/containerized-testing-with-kerberos-and-ssh/
log "Add kerberos principals"
docker exec -i kdc-server kadmin.local << EOF
addprinc -randkey host/ssh-server.kerberos-demo.local@EXAMPLE.COM
ktadd -k /sshserver.keytab host/ssh-server.kerberos-demo.local@EXAMPLE.COM
addprinc -randkey sshuser@EXAMPLE.COM
ktadd -k /sshuser.keytab sshuser@EXAMPLE.COM
listprincs
EOF

log "Copy sshuser.keytab to connect container /tmp/sshuser.keytab"
docker cp kdc-server:/sshuser.keytab .
docker cp sshuser.keytab connect:/tmp/sshuser.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/sshuser.keytab
fi

log "Copy sshserver.keytab to ssh server /etc/krb5.keytab"
docker cp kdc-server:/sshserver.keytab .
docker cp sshserver.keytab ssh-server:/etc/krb5.keytab
docker exec -u 0 ssh-server chown root:root /etc/krb5.keytab

log "Add sshuser"
docker exec -i ssh-server adduser sshuser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" << EOF
confluent
confluent
EOF

docker exec ssh-server bash -c "
mkdir -p /home/sshuser/upload/input
mkdir -p /home/sshuser/upload/error
mkdir -p /home/sshuser/upload/finished

chown -R sshuser /home/sshuser/upload
"

# FIXTHIS: it is required to do kinit manually
docker exec connect kinit sshuser -k -t /tmp/sshuser.keytab
# if required to troubleshoot
# docker exec -i --privileged --user root connect bash -c "yum update -y && yum install openssh-clients -y"

log "Creating SFTP Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "flush.size": "3",
               "schema.compatibility": "NONE",
               "format.class": "io.confluent.connect.sftp.sink.format.avro.AvroFormat",
               "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
               "sftp.username":"sshuser",
               "kerberos.keytab.path": "/tmp/sshuser.keytab",
               "kerberos.user.principal": "sshuser",
               "sftp.host":"ssh-server",
               "sftp.port":"22",
               "sftp.working.dir": "/home/sshuser/upload",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sftp-sink-kerberos/config | jq .


log "Sending messages to topic test_sftp_sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_sftp_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of ./upload/topics/test_sftp_sink/partition\=0/"
docker exec ssh-server bash -c "ls /home/sshuser/upload/topics/test_sftp_sink/partition\=0/"

docker cp ssh-server:/home/sshuser/upload/topics/test_sftp_sink/partition\=0/test_sftp_sink+0+0000000000.avro /tmp/

docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/test_sftp_sink+0+0000000000.avro