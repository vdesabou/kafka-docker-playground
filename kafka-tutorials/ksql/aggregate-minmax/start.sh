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

echo "Invoke manual steps"
docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE STREAM MOVIE_SALES (title VARCHAR, release_year INT, total_sales INT)
    WITH (KAFKA_TOPIC='movie-ticket-sales',
          PARTITIONS=1,
          VALUE_FORMAT='avro');

INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Avengers: Endgame', 2019, 856980506);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Captain Marvel', 2019, 426829839);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Toy Story 4', 2019, 401486230);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('The Lion King', 2019, 385082142);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Black Panther', 2018, 700059566);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Avengers: Infinity War', 2018, 678815482);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Deadpool 2', 2018, 324512774);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Beauty and the Beast', 2017, 517218368);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Wonder Woman', 2017, 412563408);
INSERT INTO MOVIE_SALES (title, release_year, total_sales) VALUES ('Star Wars Ep. VIII: The Last Jedi', 2017, 517218368);

SET 'auto.offset.reset' = 'earliest';
SET 'ksql.streams.cache.max.bytes.buffering' = '10000000';

SELECT RELEASE_YEAR,
       MIN(TOTAL_SALES) AS MIN__TOTAL_SALES,
       MAX(TOTAL_SALES) AS MAX__TOTAL_SALES
FROM MOVIE_SALES
GROUP BY RELEASE_YEAR
LIMIT 2;

CREATE TABLE MOVIE_FIGURES_BY_YEAR AS
    SELECT RELEASE_YEAR,
           MIN(TOTAL_SALES) AS MIN__TOTAL_SALES,
           MAX(TOTAL_SALES) AS MAX__TOTAL_SALES
    FROM MOVIE_SALES
    GROUP BY RELEASE_YEAR;

PRINT 'MOVIE_FIGURES_BY_YEAR' FROM BEGINNING LIMIT 2;
EOF


echo "Invoke the tests"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json
