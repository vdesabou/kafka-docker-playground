#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic myproducts
set -e

playground topic create --topic myproducts


cd ${DIR}/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi

rm -f server.crt
rm -f server.csr
rm -f server.key
rm -f ca.crt
rm -f ca.key

#https://blog.crunchydata.com/blog/ssl-certificate-authentication-postgresql-docker-containers
log "Creating a Root Certificate Authority (CA)"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"

log "Generate the PostgreSQL server key and certificate"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=postgres"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
rm server.csr
cp ca.crt /tmp/
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

connector_name="PostgresSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "PostgresSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "input.data.format": "AVRO",
  "connection.host": "$NGROK_HOSTNAME",
  "connection.port": "$NGROK_PORT",
  "connection.user": "myuser",
  "connection.password": "mypassword",

  "ssl.mode": "verify-full",
  "ssl.root.cert": "/tmp/ca.crt",
  "db.name": "postgres",
  "topics": "myproducts",
  "db.timezone": "UTC",
  "auto.create": "true",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Sending messages to topic myproducts"
playground topic produce -t myproducts --nb-messages 1 << 'EOF'
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

playground topic produce -t myproducts --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
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

sleep 5


log "Show content of MYPRODUCTS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM MYPRODUCTS'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

