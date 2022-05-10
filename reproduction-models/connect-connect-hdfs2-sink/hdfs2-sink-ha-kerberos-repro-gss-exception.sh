#!/bin/bash
set -e

# https://steveloughran.gitbooks.io/kerberos_and_hadoop/content/sections/errors.html
# https://stackoverflow.com/questions/34616676/should-i-call-ugi-checktgtandreloginfromkeytab-before-every-action-on-hadoop
# https://stackoverflow.com/questions/44362086/is-kinit-required-while-accessing-a-kerberized-service-through-java-code
# https://stackoverflow.com/questions/38555244/how-do-you-set-the-kerberos-ticket-lifetime-from-java
# https://serverfault.com/a/133631
# https://community.cloudera.com/t5/Support-Questions/Error-on-kerberos-ticket-renewer-role-startup/td-p/31187

#export TAG=5.4.2-1-ubi8
#export CONNECTOR_TAG=10.0.6
export ENABLE_CONNECT_NODES=1
NB_CONNECTORS=110
NB_TASK_PER_CONNECTOR=8
CONNECT_KERBEROS_TICKET_LIFETIME=5

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_gss_exception () {
     MAX_WAIT=43200
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for GSS exception to happen (it can take several hours)"
     docker container logs connect > /tmp/out.txt 2>&1
     docker container logs connect2 >> /tmp/out.txt 2>&1
     docker container logs connect3 >> /tmp/out.txt 2>&1
     while ! grep "Failed to find any Kerberos tgt" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          docker container logs connect2 >> /tmp/out.txt 2>&1
          docker container logs connect3 >> /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Failed to find any Kerberos tgt' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi

          for((i=0;i<$NB_CONNECTORS;i++)); do
               # send requests
               seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs$i --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
          done
     done
     log "The problem has been reproduced !"
}

if [ ! -f ${DIR}/hadoop-2.7.3.tar.gz ]
then
     log "Getting hadoop-2.7.3.tar.gz"
     wget https://archive.apache.org/dist/hadoop/common/hadoop-2.7.3/hadoop-2.7.3.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-ha-gss-exception.yml"

log "Java version used on connect:"
docker exec -i connect java -version

log "Wait 120 seconds while hadoop is installing"
sleep 120

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect.hdfs \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/org.apache.hadoop.security \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:18083/admin/loggers/io.confluent.connect.hdfs \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:18083/admin/loggers/org.apache.hadoop.security \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:28083/admin/loggers/io.confluent.connect.hdfs \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:28083/admin/loggers/org.apache.hadoop.security \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'


# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -chmod 777  /"

log "Add connect kerberos principal"
docker exec -i krb5 kadmin.local << EOF
addprinc -randkey connect@EXAMPLE.COM
modprinc -maxrenewlife 604800 +allow_renewable connect@EXAMPLE.COM
modprinc -maxrenewlife 604800 +allow_renewable krbtgt/EXAMPLE.COM
modprinc -maxrenewlife 604800 +allow_renewable krbtgt/EXAMPLE.COM@EXAMPLE.COM
modprinc -maxlife $CONNECT_KERBEROS_TICKET_LIFETIME connect@EXAMPLE.COM
ktadd -k /connect.keytab connect@EXAMPLE.COM
getprinc connect@EXAMPLE.COM
EOF

log "Copy connect.keytab to connect container"
docker cp krb5:/connect.keytab .
docker cp connect.keytab connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/connect.keytab
fi

log "Copy connect.keytab to connect2 container"
docker cp connect.keytab connect2:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect2 chown appuser:appuser /tmp/connect.keytab
fi

log "Copy connect.keytab to connect3 container"
docker cp connect.keytab connect3:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect3 chown appuser:appuser /tmp/connect.keytab
fi

for((i=0;i<$NB_CONNECTORS;i++)); do
     LOG_DIR="/logs$i"
     TOPIC="test_hdfs$i"
     log "Creating HDFS Sink connector $i"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
                    "tasks.max":"'"$NB_TASK_PER_CONNECTOR"'",
                    "topics": "'"$TOPIC"'",
                    "store.url":"hdfs://sh",
                    "flush.size":"3",
                    "hadoop.conf.dir":"/opt/hadoop/etc/hadoop/",
                    "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
                    "partition.field.name":"f1",
                    "rotate.interval.ms":"120000",
                    "logs.dir": "'"$LOG_DIR"'",
                    "hdfs.authentication.kerberos": "true",
                    "kerberos.ticket.renew.period.ms": "5000",
                    "connect.hdfs.principal": "connect@EXAMPLE.COM",
                    "connect.hdfs.keytab": "/tmp/connect.keytab",
                    "hdfs.namenode.principal": "nn/_HOST@EXAMPLE.COM",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs-sink-kerberos$i/config | jq .
done

wait_for_gss_exception

exit 0

log "Trigger a manual failover from nn1 to nn2"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs haadmin -failover -forceactive nn1 nn2"
