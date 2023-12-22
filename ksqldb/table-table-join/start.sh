#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

log "Create the ksqlDB tables"
log "First, we create a Kafka topic and table to represent the movie reference data. Then, Kafka topic and a second table to represent the additional movie data about leading actor"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE TABLE movies (
  title VARCHAR PRIMARY KEY,
  id INT,
  release_year INT
) WITH (
  KAFKA_TOPIC='movies',
  PARTITIONS=1,
  VALUE_FORMAT='avro'
);

CREATE TABLE lead_actor (
 title VARCHAR PRIMARY KEY,
 actor_name VARCHAR
) WITH (
 KAFKA_TOPIC='lead_actors',
 PARTITIONS=1,
 VALUE_FORMAT='avro'
);
EOF

log "Insert the records to these two tables"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

INSERT INTO MOVIES (ID, TITLE, RELEASE_YEAR) VALUES (48, 'Aliens', 1986);
INSERT INTO MOVIES (ID, TITLE, RELEASE_YEAR) VALUES (294, 'Die Hard', 1998);
INSERT INTO MOVIES (ID, TITLE, RELEASE_YEAR) VALUES (128, 'The Big Lebowski', 1998);
INSERT INTO MOVIES (ID, TITLE, RELEASE_YEAR) VALUES (42, 'The Godfather', 1998);

INSERT INTO LEAD_ACTOR (TITLE, ACTOR_NAME) VALUES ('Aliens','Sigourney Weaver');
INSERT INTO LEAD_ACTOR (TITLE, ACTOR_NAME) VALUES ('Die Hard','Bruce Willis');
INSERT INTO LEAD_ACTOR (TITLE, ACTOR_NAME) VALUES ('The Big Lebowski','Jeff Bridges');
INSERT INTO LEAD_ACTOR (TITLE, ACTOR_NAME) VALUES ('The Godfather','Al Pacino');

EOF

log "With a Table-Table join, we enrich the movie data with more information about who the lead actor in the movie is"
log "The following query does a left join between the movie table and the lead actor table."
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT M.ID, M.TITLE, M.RELEASE_YEAR, L.ACTOR_NAME
    FROM MOVIES M
    INNER JOIN LEAD_ACTOR L
    ON M.TITLE = L.TITLE
    EMIT CHANGES
    LIMIT 3;
EOF

# This should yield the following output:
#
# +--------------------+--------------------+--------------------+--------------------+
# |ID                  |M_TITLE             |RELEASE_YEAR        |ACTOR_NAME          |
# +--------------------+--------------------+--------------------+--------------------+
# |48                  |Aliens              |1986                |Sigourney Weaver    |
# |294                 |Die Hard            |1998                |Bruce Willis        |
# |128                 |The Big Lebowski    |1998                |Jeff Bridges        |
# Limit Reached
# Query terminated

log "We create a new table based on this table-table join"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE MOVIES_ENRICHED AS
    SELECT M.ID, M.TITLE, M.RELEASE_YEAR, L.ACTOR_NAME
    FROM MOVIES M
    INNER JOIN LEAD_ACTOR L
    ON M.TITLE = L.TITLE
    EMIT CHANGES;
EOF

# Wait for the stream to be initialized
sleep 5
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM MOVIES_ENRICHED;
EOF
