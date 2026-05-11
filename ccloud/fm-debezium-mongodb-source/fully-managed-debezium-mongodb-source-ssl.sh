#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic dbserver1.inventory.customers
set -e

playground topic create --topic dbserver1.inventory.customers


mkdir -p ../../ccloud/fm-debezium-mongodb-source/ssl
cd ../../ccloud/fm-debezium-mongodb-source/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

rm -f mongo.pem
rm -f mongo.crt
rm -f mongo.key

log "Create a self-signed certificate"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mongodb' -keyout /tmp/mongo.key -out /tmp/mongo.crt -days 365

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

# https://www.mongodb.com/community/forums/t/mongodb-4-4-2-x509/13868/5
cat mongo.key mongo.crt > mongo.pem

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

log "Creating JKS from pem files"
rm -f truststore.jks
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -importcert -alias mongoCACert -noprompt -file /tmp/mongo.crt -keystore /tmp/truststore.jks -storepass confluent

if [[ "$OSTYPE" == "darwin"* ]]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

base64_truststore=$(cat truststore.jks | base64 | tr -d '\n')

cd -


docker compose -f docker-compose-ssl.yml build
docker compose -f docker-compose-ssl.yml down -v --remove-orphans
docker compose -f docker-compose-ssl.yml up -d --quiet-pull

sleep 5

log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]
    then
      log "Getting ngrok hostname and port"
      NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
      NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

      if ! [[ $NGROK_PORT =~ ^[0-9]+$ ]]
      then
        log "NGROK_PORT is not a valid number, keep retrying..."
        continue
      else 
        break
      fi
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done

# https://www.mongodb.com/docs/manual/tutorial/configure-ssl-clients/
log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use admin
db.createUser(
{
user: "debezium",
pwd: "dbz",
roles: ["dbOwner"]
}
)
EOF


sleep 2

log "Insert a record"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use inventory
db.customers.find().pretty();
EOF

connector_name="MongoDbCdcSourceSSL_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "MongoDbCdcSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",

    "mongodb.connection.string": "mongodb://$NGROK_HOSTNAME:$NGROK_PORT/?replicaSet=debezium&directConnection=true",
    "mongodb.user" : "debezium",
    "mongodb.password" : "dbz",

    "mongodb.ssl.enabled": "true",
    "mongodb.ssl.invalid.hostname.allowed": "true",
    "mongodb.ssl.truststore": "data:text/plain;base64,$base64_truststore",
    "mongodb.ssl.truststore.password": "confluent",

    "topic.prefix": "dbserver1",
    "output.data.format": "AVRO",
    "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Verifying topic dbserver1.inventory.customers"
playground topic consume --topic dbserver1.inventory.customers --min-expected-messages 1 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name