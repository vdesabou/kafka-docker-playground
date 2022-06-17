#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-108463-null-bytes--type-doesn't-have-a-mapping-to-the-sql-database-column-type-error.yml"

CLUSTER_NAME=pg${USER}redshift${TAG}
CLUSTER_NAME=${CLUSTER_NAME//[-._]/}

set +e
log "Delete AWS Redshift cluster, if required"
aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot
log "Delete security group sg$CLUSTER_NAME, if required"
aws ec2 delete-security-group --group-name sg$CLUSTER_NAME
set -e

log "Create AWS Redshift cluster"
# https://docs.aws.amazon.com/redshift/latest/mgmt/getting-started-cli.html
aws redshift create-cluster --cluster-identifier $CLUSTER_NAME --master-username masteruser --master-user-password myPassword1 --node-type dc2.large --cluster-type single-node --publicly-accessible

# Verify AWS Redshift cluster has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for AWS Redshift cluster $CLUSTER_NAME to start"
aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq .Clusters[0].ClusterStatus > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "available" ]]; do
     sleep 10
     aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq .Clusters[0].ClusterStatus > /tmp/out.txt 2>&1
     CUR_WAIT=$(( CUR_WAIT+10 ))
     if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
          echo -e "\nERROR: The logs in ${CONTROL_CENTER_CONTAINER} container do not show 'available' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
          exit 1
     fi
done
log "AWS Redshift cluster $CLUSTER_NAME has started!"

log "Create a security group"
GROUP_ID=$(aws ec2 create-security-group --group-name sg$CLUSTER_NAME --description "playground aws redshift" | jq -r .GroupId)
log "Allow ingress traffic from 0.0.0.0/0 on port 5439"
aws ec2 authorize-security-group-ingress --group-id $GROUP_ID --protocol tcp --port 5439 --cidr "0.0.0.0/0"
log "Modify AWS Redshift cluster to use the security group $GROUP_ID"
aws redshift modify-cluster --cluster-identifier $CLUSTER_NAME --vpc-security-group-ids $GROUP_ID

sleep 60

# getting cluster URL
CLUSTER=$(aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq -r .Clusters[0].Endpoint.Address)


docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"object","properties":{"f1":{"type":"string"},"f2":{"oneOf": [ {"type": "null"},{"connect.type": "bytes","type": "string"}]}}}' << EOF
{"f1": "1","f2":"ZG1Gc2RXVXg="}
{"f1": "2","f2":"ZG1Gc2RXVXg="}
{"f1": "3","f2":"ZG1Gc2RXVXg="}
EOF

log "Creating AWS Redshift Sink connector with cluster url $CLUSTER"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.redshift.RedshiftSinkConnector",
               "tasks.max": "1",
               "topics": "orders",
               "aws.redshift.domain": "'"$CLUSTER"'",
               "aws.redshift.port": "5439",
               "aws.redshift.database": "dev",
               "aws.redshift.user": "masteruser",
               "aws.redshift.password": "myPassword1",
               "auto.create": "true",
               "pk.mode": "kafka",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",

               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",

               "transforms": "ReplaceField",
               "transforms.ReplaceField.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
               "transforms.ReplaceField.blacklist": "f2"
          }' \
     http://localhost:8083/connectors/redshift-sink/config | jq .

sleep 20

log "Verify data is in Redshift"
timeout 30 docker run -i debezium/postgres:10 psql -h $CLUSTER -U masteruser -d dev -p 5439 << EOF > /tmp/result.log
myPassword1
SELECT * from orders;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log


# [2022-06-17 09:16:55,757] ERROR [redshift-sink|task-0] WorkerSinkTask{id=redshift-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: null (BYTES) type doesn't have a mapping to the SQL database column type
#         at io.confluent.connect.aws.redshift.jdbc.dialect.RedshiftDatabaseDialect.getSqlType(RedshiftDatabaseDialect.java:99)
#         at io.confluent.connect.aws.redshift.jdbc.dialect.GenericDatabaseDialect.writeColumnSpec(GenericDatabaseDialect.java:1861)
#         at io.confluent.connect.aws.redshift.jdbc.dialect.GenericDatabaseDialect.lambda$writeColumnsSpec$39(GenericDatabaseDialect.java:1850)
#         at io.confluent.connect.aws.redshift.jdbc.util.ExpressionBuilder.append(ExpressionBuilder.java:560)
#         at io.confluent.connect.aws.redshift.jdbc.util.ExpressionBuilder$BasicListBuilder.of(ExpressionBuilder.java:599)
#         at io.confluent.connect.aws.redshift.jdbc.dialect.GenericDatabaseDialect.writeColumnsSpec(GenericDatabaseDialect.java:1852)
#         at io.confluent.connect.aws.redshift.jdbc.dialect.GenericDatabaseDialect.buildCreateTableStatement(GenericDatabaseDialect.java:1769)
#         at io.confluent.connect.aws.redshift.jdbc.sink.DbStructure.create(DbStructure.java:121)
#         at io.confluent.connect.aws.redshift.jdbc.sink.DbStructure.createOrAmendIfNecessary(DbStructure.java:67)
#         at io.confluent.connect.aws.redshift.jdbc.sink.BufferedRecords.add(BufferedRecords.java:122)
#         at io.confluent.connect.aws.redshift.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:74)
#         at io.confluent.connect.aws.redshift.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more
