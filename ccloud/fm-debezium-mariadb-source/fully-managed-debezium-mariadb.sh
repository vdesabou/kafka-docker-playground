#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../ccloud/fm-debezium-mysql-v2-source
cd -

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set_profiles

set +e
playground topic delete --topic mariadb.mydb.CUSTOMERS
set -e

set_profiles
docker compose build
docker compose ${profile_sql_datagen_command} down -v --remove-orphans
docker compose ${profile_sql_datagen_command} up -d --quiet-pull

sleep 30

get_ngrok_url


log "Create table"
playground db sql --database db << EOF
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
playground db sql --database db << EOF
USE mydb;

INSERT INTO CUSTOMERS (first_name, last_name, email, gender, club_status, comments) VALUES ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
EOF

connector_name="MariaDbCdcSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MariaDbCdcSource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "database.hostname": "$NGROK_HOSTNAME",
  "database.port": "$NGROK_PORT",
  "database.user": "debezium",
  "database.password": "dbz",
  "topic.prefix": "mariadb",
  "table.include.list":"mydb.CUSTOMERS",
  "output.data.format": "AVRO",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 60

log "Verifying topic mariadb.mydb.CUSTOMERS"
playground topic consume --topic mariadb.mydb.CUSTOMERS --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name