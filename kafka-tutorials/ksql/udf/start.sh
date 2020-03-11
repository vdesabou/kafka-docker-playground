#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

# notice the "EOF" -> https://unix.stackexchange.com/a/490970
log "Invoke manual steps"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << "EOF"

SHOW FUNCTIONS;
DESCRIBE FUNCTION VWAP;

CREATE STREAM raw_quotes(ticker varchar, bid int, ask int, bidqty int, askqty int)
    WITH (kafka_topic='stockquotes', value_format='avro', key='ticker', partitions=1);

INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZTEST', 15, 25, 100, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZVV',   25, 35, 100, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZVZZT', 35, 45, 100, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZXZZT', 45, 55, 100, 100);

INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZTEST', 10, 20, 50, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZVV',   30, 40, 100, 50);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZVZZT', 30, 40, 50, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZXZZT', 50, 60, 100, 50);

INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZTEST', 15, 20, 100, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZVV',   25, 35, 100, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZVZZT', 35, 45, 100, 100);
INSERT INTO raw_quotes (ticker, bid, ask, bidqty, askqty) VALUES ('ZXZZT', 45, 55, 100, 100);

SET 'auto.offset.reset' = 'earliest';

SELECT ticker, vwap(bid, bidqty, ask, askqty) AS vwap FROM raw_quotes EMIT CHANGES LIMIT 12;

CREATE STREAM vwap WITH (kafka_topic = 'vwap', partitions = 1) AS
    SELECT ticker,
           vwap(bid, bidqty, ask, askqty) AS vwap
    FROM raw_quotes
    EMIT CHANGES;

PRINT 'vwap' FROM BEGINNING LIMIT 12;

EOF
