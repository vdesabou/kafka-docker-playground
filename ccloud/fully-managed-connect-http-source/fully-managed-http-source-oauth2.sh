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
logwarn "Example in order to set EC2 Security Group with Confluent Static Egress IP Addresses and port 8080:"
logwarn "group=\$(aws ec2 describe-instances --instance-id <\$ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 8080 --cidr 13.36.88.88/32"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 8080 --cidr 13.36.88.89/32"
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

docker-compose -f docker-compose.oauth2.yml build
docker-compose -f docker-compose.oauth2.yml down -v --remove-orphans
docker-compose -f docker-compose.oauth2.yml up -d

sleep 5

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4551/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

log "Creating http-topic topic in Confluent Cloud"
set +e
create_topic http-topic
set -e

connector_name="HttpSource"
set +e
log "Deleting fully managed connector $connector_name, it might fail..."
playground ccloud-connector delete --connector $connector_name
set -e

log "Creating fully managed connector"
playground ccloud-connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "HttpSource",
     "name": "HttpSource",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topic.name.pattern": "http-topic",
     "output.data.format": "AVRO",
     "url": "http://$NGROK_HOSTNAME:$NGROK_PORT/api/messages",
     "entity.names": "AppName,User",
     "tasks.max" : "1",
     "auth.type": "oauth2",
     "oauth2.token.url": "http://$NGROK_HOSTNAME:$NGROK_PORT/oauth/token",
     "oauth2.client.id": "kc-client",
     "oauth2.client.secret": "kc-secret",
     "oauth2.client.mode": "header",
     "http.offset.mode": "SIMPLE_INCREMENTING",
     "http.initial.offset": "0"
}
EOF
wait_for_ccloud_connector_up $connector_name 300

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground ccloud-connector delete --connector $connector_name
