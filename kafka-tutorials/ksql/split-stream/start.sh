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

CREATE STREAM actingevents (name VARCHAR, title VARCHAR, genre VARCHAR)
    WITH (KAFKA_TOPIC = 'acting-events', PARTITIONS = 1, VALUE_FORMAT = 'AVRO');

INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Bill Murray', 'Ghostbusters', 'fantasy');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Christian Bale', 'The Dark Knight', 'crime');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Diane Keaton', 'The Godfather: Part II', 'crime');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Jennifer Aniston', 'Office Space', 'comedy');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Judy Garland', 'The Wizard of Oz', 'fantasy');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Keanu Reeves', 'The Matrix', 'fantasy');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Laura Dern', 'Jurassic Park', 'fantasy');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Matt Damon', 'The Martian', 'drama');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Meryl Streep', 'The Iron Lady', 'drama');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Russell Crowe', 'Gladiator', 'drama');
INSERT INTO ACTINGEVENTS (name, title,genre) VALUES ('Will Smith', 'Men in Black', 'comedy');

SET 'auto.offset.reset' = 'earliest';

SELECT NAME, TITLE FROM ACTINGEVENTS WHERE GENRE='drama' LIMIT 3;

SELECT NAME, TITLE, GENRE FROM ACTINGEVENTS WHERE GENRE != 'drama' AND GENRE != 'fantasy' LIMIT 4;

CREATE STREAM actingevents_drama AS
    SELECT NAME, TITLE
      FROM ACTINGEVENTS
     WHERE GENRE='drama';

CREATE STREAM actingevents_fantasy AS
    SELECT NAME, TITLE
      FROM ACTINGEVENTS
     WHERE GENRE='fantasy';

CREATE STREAM actingevents_other AS
    SELECT NAME, TITLE, GENRE
      FROM ACTINGEVENTS
     WHERE GENRE != 'drama'
       AND GENRE != 'fantasy';


PRINT 'ACTINGEVENTS_FANTASY' FROM BEGINNING LIMIT 4;
EOF


echo -e "\033[0;33mInvoke the tests\033[0m"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json