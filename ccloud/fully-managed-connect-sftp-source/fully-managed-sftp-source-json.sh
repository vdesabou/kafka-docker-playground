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
logwarn "Example in order to set EC2 Security Group with Confluent Static Egress IP Addresses and port 1883:"
logwarn "group=\$(aws ec2 describe-instances --instance-id <\$ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 1883 --cidr 13.36.88.88/32"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 1883 --cidr 13.36.88.89/32"
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
playground topic delete --topic sftp-testing-topic
set -e

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d

sleep 5

docker exec sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input
mkdir -p /chroot/home/foo/upload/error
mkdir -p /chroot/home/foo/upload/finished

chown -R foo /chroot/home/foo/upload
"

echo $'{"id":1,"first_name":"Roscoe","last_name":"Brentnall","email":"rbrentnall0@mediafire.com","gender":"Male","ip_address":"202.84.142.254","last_login":"2018-02-12T06:26:23Z","account_balance":1450.68,"country":"CZ","favorite_color":"#4eaefa"}\n{"id":2,"first_name":"Gregoire","last_name":"Fentem","email":"gfentem1@nsw.gov.au","gender":"Male","ip_address":"221.159.106.63","last_login":"2015-03-27T00:29:56Z","account_balance":1392.37,"country":"ID","favorite_color":"#e8f686"}' > json-sftp-source.json

docker cp json-sftp-source.json sftp-server:/chroot/home/foo/upload/input/
rm -f json-sftp-source.json



log "Getting ngrok hostname and port®"
NGROK_URL=$(curl --silent http://127.0.0.1:4551/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="SftpSource"
set +e
log "Deleting fully managed connector $connector_name, it might fail..."
playground ccloud-connector delete --connector $connector_name
set -e

log "Creating fully managed connector"
playground ccloud-connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "SftpSource",
     "name": "SftpSource",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.format": "JSON",
     "input.file.parser.format": "JSON",
     "kafka.topic": "sftp-testing-topic",
     "schema.generation.enabled": "true",
     "schema.generation.key.name": "key",
     "schema.generation.value.name": "value",
     "input.path": "/home/foo/upload/input",
     "error.path": "/home/foo/upload/error",
     "finished.path": "/home/foo/upload/finished",
     "input.file.pattern": ".*\\\.json",

     "sftp.username":"foo",
     "sftp.password":"pass",
     "sftp.host":"$NGROK_HOSTNAME",
     "sftp.port":"$NGROK_PORT",

     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 300

sleep 5

log "Verify we have received the data in sftp-testing-topic topic"
playground topic consume --topic sftp-testing-topic --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground ccloud-connector delete --connector $connector_name