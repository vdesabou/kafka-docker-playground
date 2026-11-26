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

cd ../../connect/connect-jdbc-mysql-source
if [ ! -f ${PWD}/mysql-connector-j-8.4.0.jar ]
then
     log "Downloading mysql-connector-j-8.4.0.jar"
     wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.4.0/mysql-connector-j-8.4.0.jar
fi
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
cp mysql-connector-j-8.4.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/mysql-connector-j-8.4.0.jar
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000012-jdbc-source-misses-updates.yml"

log "Create table CUSTOMERS with 3 customers"
playground db sql --database mydb << 'EOF'
CREATE TABLE CUSTOMERS (
  id          INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  first_name  VARCHAR(50),
  last_name   VARCHAR(50),
  club_status VARCHAR(20),
  update_ts   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);
INSERT INTO CUSTOMERS (first_name, last_name, club_status) VALUES ('Rica', 'Blaisdell', 'bronze');
INSERT INTO CUSTOMERS (first_name, last_name, club_status) VALUES ('Ruthie', 'Brockherst', 'platinum');
INSERT INTO CUSTOMERS (first_name, last_name, club_status) VALUES ('Mariejeanne', 'Cocci', 'bronze');
EOF

# the customer config: "id is the primary key, it always grows"
log "Creating JDBC MySQL source connector"
playground connector create-or-update --connector mysql-source << EOF
{
     "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max":"1",
     "connection.url":"jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false&allowPublicKeyRetrieval=true",
     "table.whitelist":"CUSTOMERS",
     "mode":"incrementing",
     "incrementing.column.name":"id",
     "poll.interval.ms":"1000",
     "topic.prefix":"mysql-",
     "value.converter":"io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081"
}
EOF

playground topic wait-for-records --topic mysql-CUSTOMERS --min-expected-messages 3 --max-wait 60

# the issue: Rica gets the gold status, and a new customer signs up
log "Rica is promoted to gold, and Hashim signs up"
playground db sql --database mydb << 'EOF'
UPDATE CUSTOMERS SET club_status = 'gold' WHERE id = 1;
INSERT INTO CUSTOMERS (first_name, last_name, club_status) VALUES ('Hashim', 'Rumke', 'silver');
EOF

sleep 10

log "The topic:"
playground topic consume --topic mysql-CUSTOMERS
