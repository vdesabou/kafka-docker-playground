#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${PWD}/redshift-jdbc42-2.1.0.17/redshift-jdbc42-2.1.0.17.jar ]
then
     mkdir -p redshift-jdbc42-2.1.0.17
     cd redshift-jdbc42-2.1.0.17
     wget -q https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/2.1.0.17/redshift-jdbc42-2.1.0.17.zip
     unzip redshift-jdbc42-2.1.0.17.zip
     cd -
fi

handle_aws_credentials

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.redshift.yml"



log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic orders
sleep 3
playground topic create --topic orders
set -e

CLUSTER_NAME=pg${USER}redshift${GITHUB_RUN_NUMBER}${TAG_BASE}
CLUSTER_NAME=${CLUSTER_NAME//[-._]/}

log "Delete AWS Redshift cluster, if required"
set +e
RETRIES=3
# Set the retry interval in seconds
RETRY_INTERVAL=60
# Attempt to delete the cluster
for i in $(seq 1 $RETRIES); do
    echo "Attempt $i to delete cluster $CLUSTER_NAME"
    if aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot; then
        echo "Cluster $CLUSTER_NAME deleted successfully"
        break
    else
        error=$(aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot 2>&1)
        if [[ $error == *"InvalidClusterState"* ]]; then
            echo "InvalidClusterState error encountered. Retrying in $RETRY_INTERVAL seconds..."
            sleep $RETRY_INTERVAL
        else
            echo "Error deleting cluster $CLUSTER_NAME: $error"
            exit 1
        fi
    fi
done
log "Delete security group sg$CLUSTER_NAME, if required"
aws ec2 delete-security-group --group-name sg$CLUSTER_NAME
set -e

log "Create AWS Redshift cluster"
# https://docs.aws.amazon.com/redshift/latest/mgmt/getting-started-cli.html
aws redshift create-cluster --cluster-identifier $CLUSTER_NAME --master-username masteruser --master-user-password myPassword1 --node-type ra3.large --cluster-type single-node --publicly-accessible --tags Key=cflt_managed_by,Value=user Key=cflt_managed_id,Value="$USER"

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
          logerror "❌ AWS Redshift cluster $CLUSTER_NAME has not started ! See output of aws redshift describe-clusters below:"
          cat /tmp/out.txt
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

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 3 << 'EOF'
{
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Creating AWS Redshift Sink connector with cluster url $CLUSTER"
playground connector create-or-update --connector redshift-sink  << EOF
{
     "connector.class": "io.confluent.connect.aws.redshift.RedshiftSinkConnector",
     "tasks.max": "1",
     "topics": "orders",
     "aws.redshift.domain": "$CLUSTER",
     "aws.redshift.port": "5439",
     "aws.redshift.database": "dev",
     "aws.redshift.user": "masteruser",
     "aws.redshift.password": "myPassword1",
     "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
     "aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY",
     "auto.create": "true",
     "pk.mode": "kafka"
}
EOF

sleep 20

log "Verify data is in Redshift"
timeout 30 docker run -i debezium/postgres:15-alpine psql -h $CLUSTER -U masteruser -d dev -p 5439 << EOF > /tmp/result.log
myPassword1
SELECT * from orders;
EOF
cat /tmp/result.log
grep "product" /tmp/result.log
