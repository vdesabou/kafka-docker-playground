#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Invoke manual steps"
timeout 120 docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE STREAM all_publications (author VARCHAR, title VARCHAR)
    WITH (kafka_topic = 'publication_events', partitions = 1, key = 'author', value_format = 'avro');

INSERT INTO all_publications (author, title) VALUES ('C.S. Lewis', 'The Silver Chair');
INSERT INTO all_publications (author, title) VALUES ('George R. R. Martin', 'A Song of Ice and Fire');
INSERT INTO all_publications (author, title) VALUES ('C.S. Lewis', 'Perelandra');
INSERT INTO all_publications (author, title) VALUES ('George R. R. Martin', 'Fire & Blood');
INSERT INTO all_publications (author, title) VALUES ('J. R. R. Tolkien', 'The Hobbit');
INSERT INTO all_publications (author, title) VALUES ('J. R. R. Tolkien', 'The Lord of the Rings');
INSERT INTO all_publications (author, title) VALUES ('George R. R. Martin', 'A Dream of Spring');
INSERT INTO all_publications (author, title) VALUES ('J. R. R. Tolkien', 'The Fellowship of the Ring');
INSERT INTO all_publications (author, title) VALUES ('George R. R. Martin', 'The Ice Dragon');

SET 'auto.offset.reset' = 'earliest';

SELECT author, title FROM all_publications WHERE author = 'George R. R. Martin' LIMIT 4;

CREATE STREAM george_martin WITH (kafka_topic = 'george_martin_books', partitions = 1) AS
    SELECT author, title
    FROM all_publications
    WHERE author = 'George R. R. Martin';

PRINT 'george_martin_books' FROM BEGINNING LIMIT 4;
EOF


log "Invoke the tests"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json