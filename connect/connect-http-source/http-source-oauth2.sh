#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

HTTP_SOURCE_CONNECTOR_ZIP="confluentinc-kafka-connect-http-source-0.2.0-SNAPSHOT.zip"
export CONNECTOR_ZIP="$PWD/$HTTP_SOURCE_CONNECTOR_ZIP"

source ${DIR}/../../scripts/utils.sh

get_3rdparty_file "$HTTP_SOURCE_CONNECTOR_ZIP"

if [ ! -f ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP ]
then
     logerror "ERROR: ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP is missing. You must be a Confluent Employee to run this example !"
     exit 1
fi

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.oauth2.yml"

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4551/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

URL="http://$NGROK_HOSTNAME:$NGROK_PORT/api/messages"
TOKEN_URL="http://$NGROK_HOSTNAME:$NGROK_PORT/oauth/token"

log "Creating http-source connector"

playground connector create-or-update --connector http-source << EOF
{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSourceConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "url": "$URL",
               "topic.name.pattern":"http-topic-${entityName}",
               "entity.names": "messages",
               "http.offset.mode": "SIMPLE_INCREMENTING",
               "http.initial.offset": "1",
               "auth.type": "oauth2",
               "oauth2.token.url": "$TOKEN_URL",
               "oauth2.client.id": "kc-client",
               "oauth2.client.secret": "kc-secret"
          }
EOF

sleep 3

# {
#   "error_code": 400,
#   "message": "Connector configuration is invalid and contains the following 6 error(s):\nInvalid credentials, the connector received a `401 Unauthorized` response status code for the initial request.\nInvalid credentials, the connector received a `401 Unauthorized` response status code for the initial request.\nInvalid credentials, the connector received a `401 Unauthorized` response status code for the initial request.\nInvalid credentials, the connector received a `401 Unauthorized` response status code for the initial request.\nInvalid credentials, the connector received a `401 Unauthorized` response status code for the initial request.\nInvalid credentials, the connector received a `401 Unauthorized` response status code for the initial request.\nYou can also find the above list of errors at the endpoint `/connector-plugins/{connectorType}/config/validate`"
# }

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X POST \
  http://localhost:8080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


log "Send a message to HTTP server"
curl -X PUT \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${token}" \
     --data '{"test":"value"}' \
     http://localhost:8080/api/messages | jq .


sleep 2

log "Verify we have received the data in http-topic-messages topic"
playground topic consume --topic http-topic-messages --min-expected-messages 1 --timeout 60
