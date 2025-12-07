#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
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
docker exec -i mariadb mariadb --user=root --password=password db << EOF
USE db;

CREATE TABLE team (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL
);


INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'kafka',
  'kafka@apache.org',
  NOW()
);

ALTER TABLE team AUTO_INCREMENT = 101;
describe team;
select * from team;
EOF

log "Adding an element to the table"
docker exec -i mariadb mariadb --user=root --password=password db << EOF
USE db;

INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'another',
  'another@apache.org',
  NOW()
);
EOF

log "Show content of team table:"
docker exec mariadb bash -c "mariadb --user=user --password=password db -e 'select * from team;'"

log "Creating MariaDB source connector"
playground connector create-or-update --connector mariadb-source  << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:mariadb://mariadb:3306/db?user=user&password=password&useSSL=false",
     "table.whitelist": "team",
     "mode": "timestamp+incrementing",
     "timestamp.column.name": "last_modified",
     "incrementing.column.name": "id",
     "topic.prefix": "mariadb-"
}
EOF

sleep 10

log "Verifying topic mariadb-team"
playground topic consume --topic mariadb-team --min-expected-messages 2 --timeout 60