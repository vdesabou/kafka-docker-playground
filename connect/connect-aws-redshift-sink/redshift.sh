#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/RedshiftJDBC4-1.2.20.1043.jar ]
then
     wget https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/1.2.20.1043/RedshiftJDBC4-1.2.20.1043.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

set +e
log "Delete AWS Redshift cluster, if required"
aws redshift delete-cluster --cluster-identifier playgroundcluster --skip-final-cluster-snapshot
aws ec2 delete-security-group --group-name redshiftplaygroundcluster
set -e

# https://docs.aws.amazon.com/redshift/latest/mgmt/getting-started-cli.html
aws redshift create-cluster --cluster-identifier playgroundcluster --master-username masteruser --master-user-password myPassword1 --node-type dc2.large --cluster-type single-node --publicly-accessible

# Verify AWS Redshift cluster has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for AWS Redshift cluster playgroundcluster to start"
aws redshift describe-clusters --cluster-identifier playgroundcluster | jq .Clusters[0].ClusterStatus > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "available" ]]; do
     sleep 10
     aws redshift describe-clusters --cluster-identifier playgroundcluster | jq .Clusters[0].ClusterStatus > /tmp/out.txt 2>&1
     CUR_WAIT=$(( CUR_WAIT+10 ))
     if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
          echo -e "\nERROR: The logs in ${CONTROL_CENTER_CONTAINER} container do not show 'available' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
          exit 1
     fi
done
log "AWS Redshift cluster playgroundcluster has started!"

PUBLIC_IP=$(curl ifconfig.me)
log "Create a security group"
GROUP_ID=$(aws ec2 create-security-group --group-name redshiftplaygroundcluster --description "playground aws redshift" | jq -r .GroupId)
log "Allow ingress traffic from public ip on port 5439"
aws ec2 authorize-security-group-ingress --group-id $GROUP_ID --protocol tcp --port 5439 --cidr $PUBLIC_IP/24
log "Modify AWS Redshift cluster to use the security group"
aws redshift modify-cluster --cluster-identifier playgroundcluster --vpc-security-group-ids $GROUP_ID

# getting cluster URL
CLUSTER=$(aws redshift describe-clusters --cluster-identifier playgroundcluster | jq -r .Clusters[0].Endpoint.Address)

log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

log "Creating AWS Redshift Logs Source connector"
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
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/redshift-sink/config | jq .

sleep 20

log "Verify data is in Redshift"
timeout 30 docker run -i debezium/postgres:10 psql -h $CLUSTER -U masteruser -d dev -p 5439 << EOF
myPassword1
SELECT * from orders;
EOF

log "Sleeping"
sleep 240

log "Delete AWS Redshift cluster"
aws redshift delete-cluster --cluster-identifier playgroundcluster --skip-final-cluster-snapshot
log "Delete security group"
aws ec2 delete-security-group --group-name redshiftplaygroundcluster
