#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${PWD}/redshift-jdbc42-2.1.0.17/redshift-jdbc42-2.1.0.17.jar ]
then
     mkdir -p redshift-jdbc42-2.1.0.17
     cd redshift-jdbc42-2.1.0.17
     wget https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/2.1.0.17/redshift-jdbc42-2.1.0.17.zip
     unzip redshift-jdbc42-2.1.0.17.zip
     cd -
fi

if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
then
     logerror "ERROR: either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
     exit 1
else
    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
    then
        log "💭 Using environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    else
        if [ -f $HOME/.aws/credentials ]
        then
            logwarn "💭 AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set based on $HOME/.aws/credentials"
            export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials| awk -F'=' '{print $2;}' )
            export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials| awk -F'=' '{print $2;}' ) 
        fi
    fi
    if [ -z "$AWS_REGION" ]
    then
        AWS_REGION=$(aws configure get region | tr '\r' '\n')
        if [ "$AWS_REGION" == "" ]
        then
            logerror "ERROR: either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
            exit 1
        fi
    fi
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

CLUSTER_NAME=pg${USER}jdbcredshift${TAG}
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

set +e
docker run -i -e CLUSTER="$CLUSTER" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" << EOF
myPassword1
DROP TABLE CUSTOMERS;
EOF
set -e

log "Create database in Redshift"
docker run -i -e CLUSTER="$CLUSTER" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" -f "/tmp/customers.sql" << EOF
myPassword1
EOF

log "Verify data is in Redshift"
docker run -i -e CLUSTER="$CLUSTER" -v "${DIR}/customers.sql":/tmp/customers.sql debezium/postgres:15-alpine psql -h "$CLUSTER" -U "masteruser" -d "dev" -p "5439" << EOF
myPassword1
SELECT * from CUSTOMERS;
EOF

log "Creating JDBC AWS Redshift source connector"
playground connector create-or-update --connector redshift-jdbc-source << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:postgresql://$CLUSTER:5439/dev?user=masteruser&password=myPassword1&ssl=false",
     "table.whitelist": "customers",
     "mode": "timestamp+incrementing",
     "timestamp.column.name": "update_ts",
     "incrementing.column.name": "id",
     "topic.prefix": "redshift-",
     "validate.non.null":"false",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF

# [2023-07-24 16:31:50,676] ERROR [redshift-jdbc-source|worker] Error while trying to get updated table list, ignoring and waiting for next table poll interval (io.confluent.connect.jdbc.source.TableMonitorThread:178)
# org.postgresql.util.PSQLException: ERROR: type "e" does not exist
#         at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2676)
#         at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2366)
#         at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:356)
#         at org.postgresql.jdbc.PgStatement.executeInternal(PgStatement.java:496)
#         at org.postgresql.jdbc.PgStatement.execute(PgStatement.java:413)
#         at org.postgresql.jdbc.PgStatement.executeWithFlags(PgStatement.java:333)
#         at org.postgresql.jdbc.PgStatement.executeCachedSql(PgStatement.java:319)
#         at org.postgresql.jdbc.PgStatement.executeWithFlags(PgStatement.java:295)
#         at org.postgresql.jdbc.PgStatement.executeQuery(PgStatement.java:244)
#         at org.postgresql.jdbc.PgDatabaseMetaData.getTables(PgDatabaseMetaData.java:1343)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.tableIds(GenericDatabaseDialect.java:428)
#         at io.confluent.connect.jdbc.source.TableMonitorThread.updateTables(TableMonitorThread.java:175)
#         at io.confluent.connect.jdbc.source.TableMonitorThread.run(TableMonitorThread.java:85)


sleep 5

log "Verifying topic redshift-customers"
playground topic consume --topic redshift-customers --min-expected-messages 5 --timeout 60
