#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jdbc-mariadb-source
if [ ! -f ${PWD}/mariadb-java-client-3.2.0.jar ]
then
     log "Downloading mariadb-java-client-3.2.0.jar"
     wget https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/3.2.0/mariadb-java-client-3.2.0.jar
fi
cd -

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

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
playground connector create-or-update --connector mariadb-source << EOF
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