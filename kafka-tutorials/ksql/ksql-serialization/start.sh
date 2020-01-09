#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

echo -e "\033[0;33mInvoke manual steps\033[0m"
docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE STREAM movies_json (movie_id BIGINT, title VARCHAR, release_year INT)
    WITH (KAFKA_TOPIC='json-movies',
          PARTITIONS=1,
          VALUE_FORMAT='json');

INSERT INTO movies_json (movie_id, title, release_year) VALUES (1, 'Lethal Weapon', 1992);
INSERT INTO movies_json (movie_id, title, release_year) VALUES (2, 'Die Hard', 1988);
INSERT INTO movies_json (movie_id, title, release_year) VALUES (3, 'Predator', 1997);

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM movies_avro
    WITH (KAFKA_TOPIC='avro-movies', VALUE_FORMAT='avro') AS
    SELECT * FROM movies_json;

PRINT 'avro-movies' FROM BEGINNING LIMIT 3;
EOF


echo -e "\033[0;33mInvoke the tests\033[0m"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json