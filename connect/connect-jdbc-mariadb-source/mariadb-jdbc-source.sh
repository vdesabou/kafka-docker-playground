#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

cd ../../connect/connect-jdbc-mariadb-source
if [ ! -f ${PWD}/mariadb-java-client-3.2.0.jar ]
then
     log "Downloading mariadb-java-client-3.2.0.jar"
     wget -q https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/3.2.0/mariadb-java-client-3.2.0.jar
fi
cd -


cd ../../connect/connect-jdbc-mariadb-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
cp ../../connect/connect-jdbc-mariadb-source/mariadb-java-client-3.2.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/mariadb-java-client-3.2.0.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create table"
playground container exec --container mariadb --command "mariadb --user=root --password=password db" << EOF
USE db;

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
playground container exec --container mariadb --command "mariadb --user=root --password=password db" << EOF
USE db;

INSERT INTO CUSTOMERS (first_name, last_name, email, gender, club_status, comments) VALUES ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
EOF

log "Show content of CUSTOMERS table:"
playground container exec --container mariadb --command "bash -c \"mariadb --user=user --password=password db -e 'select * from CUSTOMERS;'\""

log "Creating MariaDB source connector"
playground connector create-or-update --connector mariadb-source  << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:mariadb://mariadb:3306/db?user=user&password=password&useSSL=false",
     "table.whitelist": "CUSTOMERS",
     "mode": "timestamp+incrementing",
     "timestamp.column.name": "update_ts",
     "incrementing.column.name": "id",
     "topic.prefix": "mariadb-"
}
EOF

sleep 10

log "Verifying topic mariadb-CUSTOMERS"
playground topic consume --topic mariadb-CUSTOMERS --min-expected-messages 2 --timeout 60