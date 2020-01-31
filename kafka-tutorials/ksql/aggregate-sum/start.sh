#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Invoke manual steps"
timeout 120 docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE STREAM MOVIE_TICKET_SALES (title VARCHAR, sale_ts VARCHAR, ticket_total_value INT)
    WITH (KAFKA_TOPIC='movie-ticket-sales',
          PARTITIONS=1,
          VALUE_FORMAT='avro',
          TIMESTAMP='sale_ts',
          TIMESTAMP_FORMAT='yyyy-MM-dd''T''HH:mm:ssX');

INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('Die Hard',         '2019-07-18T10:00:00Z', 12);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('Die Hard',         '2019-07-18T10:01:00Z', 12);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('The Godfather',    '2019-07-18T10:01:31Z', 12);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('Die Hard',         '2019-07-18T10:01:36Z', 24);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('The Godfather',    '2019-07-18T10:02:00Z', 18);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('The Big Lebowski', '2019-07-18T11:03:21Z', 12);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('The Big Lebowski', '2019-07-18T11:03:50Z', 12);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('The Godfather',    '2019-07-18T11:40:00Z', 36);
INSERT INTO MOVIE_TICKET_SALES (title, sale_ts, ticket_total_value) VALUES ('The Godfather',    '2019-07-18T11:40:09Z', 18);

SET 'auto.offset.reset' = 'earliest';
SET 'ksql.streams.cache.max.bytes.buffering' = '10000000';

SELECT TITLE,
       SUM(TICKET_TOTAL_VALUE) AS TOTAL_VALUE
FROM MOVIE_TICKET_SALES
GROUP BY TITLE
LIMIT 3;

CREATE TABLE MOVIE_REVENUE AS
    SELECT TITLE,
           SUM(TICKET_TOTAL_VALUE) AS TOTAL_VALUE
    FROM MOVIE_TICKET_SALES
    GROUP BY TITLE;

PRINT 'MOVIE_REVENUE' FROM BEGINNING LIMIT 3;
EOF


log "Invoke the tests"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json
