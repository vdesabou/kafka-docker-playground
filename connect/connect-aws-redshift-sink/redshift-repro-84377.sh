#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/RedshiftJDBC4-1.2.20.1043.jar ]
then
     wget https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/1.2.20.1043/RedshiftJDBC4-1.2.20.1043.jar
fi

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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

# getting cluster URL
CLUSTER=$(aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq -r .Clusters[0].Endpoint.Address)


log "Sending JSON message to topic orders"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic orders << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
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
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/redshift-sink/config | jq .

sleep 20

# [2022-01-12 14:08:55,579] ERROR [redshift-sink|task-0] WorkerSinkTask{id=redshift-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: class java.util.HashMap cannot be cast to class org.apache.kafka.connect.data.Struct (java.util.HashMap is in module java.base of loader 'bootstrap'; org.apache.kafka.connect.data.Struct is in unnamed module of loader 'app') (org.apache.kafka.connect.runtime.WorkerSinkTask:636)
# java.lang.ClassCastException: class java.util.HashMap cannot be cast to class org.apache.kafka.connect.data.Struct (java.util.HashMap is in module java.base of loader 'bootstrap'; org.apache.kafka.connect.data.Struct is in unnamed module of loader 'app')
#         at io.confluent.connect.aws.redshift.jdbc.sink.PreparedStatementBinder.bindRecord(PreparedStatementBinder.java:61)
#         at io.confluent.connect.aws.redshift.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:182)
#         at io.confluent.connect.aws.redshift.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:72)
#         at io.confluent.connect.aws.redshift.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:74)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-12 14:08:55,584] ERROR [redshift-sink|task-0] WorkerSinkTask{id=redshift-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.ClassCastException: class java.util.HashMap cannot be cast to class org.apache.kafka.connect.data.Struct (java.util.HashMap is in module java.base of loader 'bootstrap'; org.apache.kafka.connect.data.Struct is in unnamed module of loader 'app')
#         at io.confluent.connect.aws.redshift.jdbc.sink.PreparedStatementBinder.bindRecord(PreparedStatementBinder.java:61)
#         at io.confluent.connect.aws.redshift.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:182)
#         at io.confluent.connect.aws.redshift.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:72)
#         at io.confluent.connect.aws.redshift.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:74)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more

log "Verify data is in Redshift"
timeout 30 docker run -i debezium/postgres:10 psql -h $CLUSTER -U masteruser -d dev -p 5439 << EOF > /tmp/result.log
myPassword1
SELECT * from orders;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

set +e
log "Delete AWS Redshift cluster"
aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot
log "Delete security group sg$CLUSTER_NAME"
aws ec2 delete-security-group --group-name sg$CLUSTER_NAME
