#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

handle_aws_credentials

bootstrap_ccloud_environment

set +e
playground topic delete --topic orders
sleep 3
playground topic create --topic orders --nb-partitions 1
set -e

CLUSTER_NAME=pgfm${USER}redshift${GITHUB_RUN_NUMBER}${TAG_BASE}
CLUSTER_NAME=${CLUSTER_NAME//[-._]/}

PASSWORD=$(date +%s | cksum | base64 | head -c 32 ; echo)
PASSWORD="${PASSWORD}1"

log "Delete AWS Redshift cluster, if required"
set +e
RETRIES=3
# Set the retry interval in seconds
RETRY_INTERVAL=60
# Attempt to delete the cluster
for i in $(seq 1 $RETRIES); do
    log "Attempt $i to delete cluster $CLUSTER_NAME"
    if aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot
    then
        log "Cluster $CLUSTER_NAME deleted successfully"
        sleep 120
        log "Delete security group sg$CLUSTER_NAME, if required"
        aws ec2 delete-security-group --group-name sg$CLUSTER_NAME
        break
    else
        error=$(aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot 2>&1)
        if [[ $error == *"InvalidClusterState"* ]]
        then
            logwarn "InvalidClusterState error encountered. Retrying in $RETRY_INTERVAL seconds..."
            sleep $RETRY_INTERVAL
        else
            logwarn "Error deleting cluster $CLUSTER_NAME: $error"
        fi
    fi
done
log "Delete security group sg$CLUSTER_NAME, if required"
aws ec2 delete-security-group --group-name sg$CLUSTER_NAME
set -e

log "Create AWS Redshift cluster"
# https://docs.aws.amazon.com/redshift/latest/mgmt/getting-started-cli.html
aws redshift create-cluster --cluster-identifier $CLUSTER_NAME --master-username masteruser --master-user-password "$PASSWORD" --node-type ra3.large --cluster-type single-node --publicly-accessible --tags Key=cflt_managed_by,Value=user Key=cflt_managed_id,Value="$USER"

function cleanup_cloud_resources {
  set +e
  log "Delete AWS Redshift cluster $CLUSTER_NAME"
  check_if_continue
  aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot
  log "Delete security group sg$CLUSTER_NAME, if required"
  aws ec2 delete-security-group --group-name sg$CLUSTER_NAME
}
trap cleanup_cloud_resources EXIT

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
          echo -e "\nERROR: The logs in ${CONTROL_CENTER_CONTAINER} container do not show 'available' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'playground container logs --open --container <container>'.\n"
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

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
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
  ]
}
EOF

playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
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
  ]
}
EOF

connector_name="RedshiftSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

# getting cluster URL
CLUSTER=$(aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq -r .Clusters[0].Endpoint.Address)

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "RedshiftSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "orders",
  "input.data.format": "AVRO",
  "aws.redshift.domain": "$CLUSTER",
  "aws.redshift.port": "5439",
  "aws.redshift.database": "dev",
  "aws.redshift.user": "masteruser",
  "aws.redshift.password": "$PASSWORD",
  "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
  "aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY",
  "auto.create": "true",
  "pk.mode": "kafka",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 20

log "Verify data is in Redshift"
timeout 30 docker run -i postgres:15 psql -h $CLUSTER -U masteruser -d dev -p 5439 << EOF > /tmp/result.log
$PASSWORD
SELECT * from orders;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
