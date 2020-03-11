#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Invoke manual steps"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

CREATE TABLE movies (ROWKEY INT KEY, title VARCHAR, release_year INT)
    WITH (kafka_topic='movies', partitions=1, value_format='avro');

CREATE STREAM ratings (ROWKEY INT KEY, rating DOUBLE)
    WITH (kafka_topic='ratings', partitions=1, value_format='avro');

INSERT INTO movies (rowkey, title, release_year) VALUES (294, 'Die Hard', 1998);
INSERT INTO movies (rowkey, title, release_year) VALUES (354, 'Tree of Life', 2011);
INSERT INTO movies (rowkey, title, release_year) VALUES (782, 'A Walk in the Clouds', 1995);
INSERT INTO movies (rowkey, title, release_year) VALUES (128, 'The Big Lebowski', 1998);
INSERT INTO movies (rowkey, title, release_year) VALUES (780, 'Super Mario Bros.', 1993);

INSERT INTO ratings (rowkey, rating) VALUES (294, 8.2);
INSERT INTO ratings (rowkey, rating) VALUES (294, 8.5);
INSERT INTO ratings (rowkey, rating) VALUES (354, 9.9);
INSERT INTO ratings (rowkey, rating) VALUES (354, 9.7);
INSERT INTO ratings (rowkey, rating) VALUES (782, 7.8);
INSERT INTO ratings (rowkey, rating) VALUES (782, 7.7);
INSERT INTO ratings (rowkey, rating) VALUES (128, 8.7);
INSERT INTO ratings (rowkey, rating) VALUES (128, 8.4);
INSERT INTO ratings (rowkey, rating) VALUES (780, 2.1);

SET 'auto.offset.reset' = 'earliest';

SELECT ratings.rowkey AS ID, title, release_year, rating FROM ratings LEFT JOIN movies ON ratings.rowkey = movies.rowkey EMIT CHANGES LIMIT 9;

CREATE STREAM rated_movies
    WITH (kafka_topic='rated_movies',
          partitions=1,
          value_format='avro') AS
    SELECT ratings.rowkey, title, rating
    FROM ratings
    LEFT JOIN movies ON ratings.rowkey = movies.rowkey;

PRINT 'rated_movies' FROM BEGINNING LIMIT 9;
EOF


log "Invoke the tests"
docker exec ksqldb-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json | grep "Test passed!"
