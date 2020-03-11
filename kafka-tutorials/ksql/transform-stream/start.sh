#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Invoke manual steps"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQLDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

CREATE STREAM raw_movies (ROWKEY INT KEY, id INT, title VARCHAR, genre VARCHAR)
    WITH (kafka_topic='movies', partitions=1, key='id', value_format = 'avro');

INSERT INTO raw_movies (id, title, genre) VALUES (294, 'Die Hard::1988', 'action');
INSERT INTO raw_movies (id, title, genre) VALUES (354, 'Tree of Life::2011', 'drama');
INSERT INTO raw_movies (id, title, genre) VALUES (782, 'A Walk in the Clouds::1995', 'romance');
INSERT INTO raw_movies (id, title, genre) VALUES (128, 'The Big Lebowski::1998', 'comedy');

SET 'auto.offset.reset' = 'earliest';

SELECT id, split(title, '::')[1] as title, split(title, '::')[2] AS year, genre FROM raw_movies EMIT CHANGES LIMIT 4;

CREATE STREAM movies WITH (kafka_topic = 'parsed_movies', partitions = 1) AS
    SELECT id,
           split(title, '::')[1] as title,
           CAST(split(title, '::')[2] AS INT) AS year,
           genre
    FROM raw_movies;

PRINT 'parsed_movies' FROM BEGINNING LIMIT 4;
EOF


log "Invoke the tests"
docker exec ksqldb-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json | grep "Test passed!"