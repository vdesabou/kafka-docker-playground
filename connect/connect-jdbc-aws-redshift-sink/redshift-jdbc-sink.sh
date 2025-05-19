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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

CLUSTER_NAME=pg${USER}jdbcredshift${TAG}
CLUSTER_NAME=${CLUSTER_NAME//[-._]/}

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
aws redshift create-cluster --cluster-identifier $CLUSTER_NAME --master-username masteruser --master-user-password myPassword1 --node-type dc2.large --cluster-type single-node --publicly-accessible --tags "cflt_managed_by=user,cflt_managed_id=$USER"

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

set +e
docker run -i -e CLUSTER="$CLUSTER" debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" << EOF
myPassword1
DROP TABLE orders;
EOF
set -e

# need to pre-create otherwise getting ConnectException: null (INT32) type doesn't have a mapping to the SQL database column type
docker run -i -e CLUSTER="$CLUSTER" debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" << EOF
myPassword1
     create table orders (id INT,product TEXT,quantity INT,price REAL);
EOF


log "Creating JDBC AWS Redshift sink connector"
playground connector create-or-update --connector redshift-jdbc-sink  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:redshift://$CLUSTER:5439/dev?user=masteruser&password=myPassword1&ssl=true&reWriteBatchedInserts=true&reWriteBatchedInsertsSize=512",
  "topics": "orders",
  "auto.create": "false",
  "auto.evolve": "false",
  "insert.mode": "insert",
  "batch.size": "512"
}
EOF

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 512 << 'EOF'
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

sleep 10

log "Verify data is in Redshift"
docker run -i -e CLUSTER="$CLUSTER" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" << EOF
myPassword1
SELECT * from orders;
EOF