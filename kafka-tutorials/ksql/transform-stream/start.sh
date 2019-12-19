#!/bin/bash

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

echo -e "\033[0;33mInvoke manual steps\033[0m"
docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE STREAM raw_movies (id int, title varchar, genre varchar)
    WITH (kafka_topic='movies', partitions=1, key='id', value_format = 'avro');

INSERT INTO raw_movies (id, title, genre) VALUES (294, 'Die Hard::1988', 'action');
INSERT INTO raw_movies (id, title, genre) VALUES (354, 'Tree of Life::2011', 'drama');
INSERT INTO raw_movies (id, title, genre) VALUES (782, 'A Walk in the Clouds::1995', 'romance');
INSERT INTO raw_movies (id, title, genre) VALUES (128, 'The Big Lebowski::1998', 'comedy');

SET 'auto.offset.reset' = 'earliest';

SELECT id, split(title, '::')[0] as title, split(title, '::')[1] AS year, genre FROM raw_movies LIMIT 4;

CREATE STREAM movies WITH (kafka_topic = 'parsed_movies', partitions = 1) AS
    SELECT id,
           split(title, '::')[0] as title,
           CAST(split(title, '::')[1] AS INT) AS year,
           genre
    FROM raw_movies;

PRINT 'parsed_movies' FROM BEGINNING LIMIT 4;
EOF


echo -e "\033[0;33mInvoke the tests\033[0m"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json