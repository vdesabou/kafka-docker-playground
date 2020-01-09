#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Invoke manual steps"
docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE STREAM ratings (title VARCHAR, release_year INT, rating DOUBLE, timestamp VARCHAR)
    WITH (kafka_topic='ratings',
          key='title',
          timestamp='timestamp',
          timestamp_format='yyyy-MM-dd HH:mm:ss',
          partitions=1,
          value_format='avro');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Die Hard', 1998, 8.2, '2019-07-09 01:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Die Hard', 1998, 4.5, '2019-07-09 05:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Die Hard', 1998, 5.1, '2019-07-09 07:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Tree of Life', 2011, 4.9, '2019-07-09 09:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Tree of Life', 2011, 5.6, '2019-07-09 08:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('A Walk in the Clouds', 1995, 3.6, '2019-07-09 12:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('A Walk in the Clouds', 1995, 6.0, '2019-07-09 15:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('A Walk in the Clouds', 1995, 4.6, '2019-07-09 22:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('The Big Lebowski', 1998, 9.9, '2019-07-09 05:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('The Big Lebowski', 1998, 4.2, '2019-07-09 02:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Super Mario Bros.', 1993, 3.5, '2019-07-09 18:00:00');

SET 'auto.offset.reset' = 'earliest';

SELECT title,
       COUNT(*) AS rating_count,
       WINDOWSTART() AS window_start,
       WINDOWEND() AS window_end
FROM ratings
WINDOW TUMBLING (SIZE 6 HOURS)
GROUP BY title
LIMIT 11;

CREATE TABLE rating_count
    WITH (kafka_topic='rating_count') AS
    SELECT title,
           COUNT(*) AS rating_count,
           WINDOWSTART() AS window_start,
           WINDOWEND() AS window_end
    FROM ratings
    WINDOW TUMBLING (SIZE 6 HOURS)
    GROUP BY title;

SELECT title,
       rating_count,
       TIMESTAMPTOSTRING(window_start, 'yyy-MM-dd HH:mm:ss'),
       TIMESTAMPTOSTRING(window_end, 'yyy-MM-dd HH:mm:ss')
FROM rating_count
LIMIT 11;

PRINT 'rating_count' FROM BEGINNING LIMIT 11;
EOF


log "Invoke the tests"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json
