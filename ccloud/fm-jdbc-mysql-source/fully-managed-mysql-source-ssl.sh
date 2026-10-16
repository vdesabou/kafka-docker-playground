#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment


set +e
playground topic delete --topic mysql-CUSTOMERS
set -e

playground topic create --topic mysql-CUSTOMERS

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 15

log "Getting certs from mysql container and transform them to JKS"
mkdir -p ${PWD}/ssl/
rm -rf ${PWD}/ssl/*
# https://dev.mysql.com/doc/connector-j/5.1/en/connector-j-reference-using-ssl.html
playground container cp --source mysql:/var/lib/mysql/ca.pem --destination ${PWD}/ssl/
playground container cp --source mysql:/var/lib/mysql/client-key.pem --destination ${PWD}/ssl/
playground container cp --source mysql:/var/lib/mysql/client-cert.pem --destination ${PWD}/ssl/

log "Creating JKS from pem files"
cd ${PWD}/ssl/
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -importcert -alias MySQLCACert -noprompt -file /tmp/ca.pem -keystore /tmp/truststore.jks -storepass mypassword
# Convert the client key and certificate files to a PKCS #12 archive
docker run --quiet --rm -v $PWD:/tmp alpine/openssl pkcs12 -export -in /tmp/client-cert.pem -inkey /tmp/client-key.pem -name "mysqlclient" -passout pass:mypassword -out /tmp/client-keystore.p12
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
# Import the client key and certificate into a Java keystore:
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -importkeystore -srckeystore /tmp/client-keystore.p12 -srcstoretype pkcs12 -srcstorepass mypassword -destkeystore /tmp/keystore.jks -deststoretype JKS -deststorepass mypassword
cd -

log "Create table"
docker exec -i mysql mysql --user=root --password=password --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=mydb << EOF
USE mydb;

CREATE TABLE CUSTOMERS (
  id          INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  first_name  VARCHAR(50),
  last_name   VARCHAR(50),
  email       VARCHAR(50),
  gender      VARCHAR(50),
  club_status VARCHAR(20),
  comments    VARCHAR(90),
  create_ts   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  update_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);


INSERT INTO CUSTOMERS (first_name, last_name, email, gender, club_status, comments) VALUES ('Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');

describe CUSTOMERS;
select * from CUSTOMERS;
EOF

log "Adding an element to the table"
docker exec -i mysql mysql --user=root --password=password --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=mydb << EOF
USE mydb;

INSERT INTO CUSTOMERS (first_name, last_name, email, gender, club_status, comments) VALUES ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
EOF

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

connector_name="MySqlSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

base64_truststore=$(cat $PWD/ssl/truststore.jks | base64 | tr -d '\n')

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MySqlSource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "output.data.format": "JSON",
  "connection.host": "$NGROK_HOSTNAME",
  "connection.port": "$NGROK_PORT",
  "connection.user": "userssl",
  "connection.password": "password",
  "db.name": "mydb",
  "table.whitelist": "CUSTOMERS",
  "db.timezone": "UTC",
  "timestamp.column.name":"update_ts",
  "incrementing.column.name":"id",
  "topic.prefix":"mysql-",
  "tasks.max": "1",
  "ssl.mode": "require",
  "ssl.truststorefile": "data:text/plain;base64,$base64_truststore",
  "ssl.truststorepassword": "mypassword"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Verifying topic mysql-CUSTOMERS"
playground topic consume --topic mysql-CUSTOMERS --min-expected-messages 2 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
