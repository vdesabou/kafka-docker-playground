#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

if [ -z "$NGROK_AUTH_TOKEN" ]
then
     logerror "NGROK_AUTH_TOKEN is not set. Export it as environment variable or pass it as argument"
     logerror "Sign up at: https://dashboard.ngrok.com/signup"
     logerror "If you have already signed up, make sure your authtoken is installed."
     logerror "Your authtoken is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken"
     exit 1
fi

logwarn "🚨WARNING🚨"
logwarn "It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using Ngrok (https://ngrok.com)."
logwarn "It is strongly encouraged to run it on a AWS EC2 instance where you'll use Confluent Static Egress IP Addresses (https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using EC2 Security Group."
logwarn ""
logwarn "Example in order to set EC2 Security Group with Confluent Static Egress IP Addresses and port 1521:"
logwarn "group=\$(aws ec2 describe-instances --instance-id <\$ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 1521 --cidr 13.36.88.88/32"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 1521 --cidr 13.36.88.89/32"
logwarn "etc..."
check_if_continue

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

set +e
delete_topic XE.MYUSER.CUSTOMERS
delete_topic redo-log-topic
set -e

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "04_populate_customer.sh" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show '04_populate_customer.sh' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"


log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4551/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="OracleCdcSource"
set +e
log "Deleting fully managed connector $connector_name, it might fail..."
playground ccloud-connector delete --connector $connector_name
set -e

log "Creating fully managed connector"
playground ccloud-connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "OracleCdcSource",
     "name": "OracleCdcSource",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.key.format": "AVRO",
     "output.data.value.format": "AVRO",
     "oracle.server": "$NGROK_HOSTNAME",
     "oracle.port": "$NGROK_PORT",
     "oracle.sid": "XE",
     "oracle.username": "MYUSER",
     "oracle.password": "password",
     "table.inclusion.regex": ".*CUSTOMERS.*",
     "start.from": "snapshot",
     "query.timeout.ms": "60000",
     "redo.log.row.fetch.size": "1",
     "redo.log.topic.name": "redo-log-topic",
     "table.topic.name.template": "\${databaseName}.\${schemaName}.\${tableName}",
     "lob.topic.name.template":"\${databaseName}.\${schemaName}.\${tableName}.\${columnName}",
     "numeric.mapping": "best_fit_or_decimal",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 300

log "Waiting 20s for connector to read existing data"
sleep 20

log "Running SQL scripts"
for script in ../../ccloud/fully-managed-connect-cdc-oracle19-source/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic XE.MYUSER.CUSTOMERS: there should be 13 records"
playground topic consume --topic XE.MYUSER.CUSTOMERS --min-expected-messages 13 --timeout 60


log "Verifying topic redo-log-topic: there should be 15 records"
playground topic consume --topic redo-log-topic --min-expected-messages 15 --timeout 60

log "🚚 If you're planning to inject more data, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/README.md#note-on-redologrowfetchsize"


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground ccloud-connector delete --connector $connector_name