#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Invoke manual steps"
docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE TABLE movies (id INT, title VARCHAR, release_year INT)
             WITH (KAFKA_TOPIC='movies',
                   PARTITIONS=1,
                   VALUE_FORMAT='avro');

CREATE TABLE lead_actor (title VARCHAR, actor_name VARCHAR)
             WITH (KAFKA_TOPIC='lead_actors',
                   PARTITIONS=1,
                   VALUE_FORMAT='avro');

INSERT INTO MOVIES (ROWKEY, ID, TITLE, RELEASE_YEAR) VALUES ('Die Hard', 294, 'Die Hard', 1998);
INSERT INTO MOVIES (ROWKEY, ID, TITLE, RELEASE_YEAR) VALUES ('The Big Lebowski', 128, 'The Big Lebowski', 1998);
INSERT INTO MOVIES (ROWKEY, ID, TITLE, RELEASE_YEAR) VALUES ('The Godfather', 42, 'The Godfather', 1998);

INSERT INTO LEAD_ACTOR (ROWKEY, TITLE, ACTOR_NAME) VALUES ('Die Hard','Die Hard','Bruce Willis');
INSERT INTO LEAD_ACTOR (ROWKEY, TITLE, ACTOR_NAME) VALUES ('The Big Lebowski','The Big Lebowski','Jeff Bridges');
INSERT INTO LEAD_ACTOR (ROWKEY, TITLE, ACTOR_NAME) VALUES ('The Godfather','The Godfather','Al Pacino');

SET 'auto.offset.reset' = 'earliest';

SELECT M.ID, M.TITLE, M.RELEASE_YEAR, L.ACTOR_NAME
FROM MOVIES M
INNER JOIN LEAD_ACTOR L
ON M.ROWKEY=L.ROWKEY
LIMIT 3;

CREATE TABLE MOVIES_ENRICHED AS
    SELECT M.ID, M.TITLE, M.RELEASE_YEAR, L.ACTOR_NAME
    FROM MOVIES M
    INNER JOIN LEAD_ACTOR L
    ON M.ROWKEY=L.ROWKEY;

PRINT MOVIES_ENRICHED FROM BEGINNING LIMIT 3;
EOF


log "Invoke the tests"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json
