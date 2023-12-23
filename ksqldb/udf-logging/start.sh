#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/udf-simple-logging/target/udf-simple-logging-1.0.0.jar ]
then
    log "Building udf-simple-logging jar"
    docker run -i --rm -v "${DIR}/udf-simple-logging":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/udf-simple-logging/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

if [ ! -f ${DIR}/udf-custom-logger/target/udf-custom-logger-1.0.0-jar-with-dependencies.jar ]
then
    log "Building udf-custom-logger jar"
    docker run -i --rm -v "${DIR}/udf-custom-logger":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/udf-custom-logger/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating streams with UDF and inserting data..."
docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [[ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ]] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF
DESCRIBE FUNCTION formula_simple_log4j_logging;

DESCRIBE FUNCTION formula_custom_log4j_logging_level;

DESCRIBE FUNCTION formula_custom_logger;

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM s1 (
    a VARCHAR KEY,
    b INT,
    c INT
) WITH (
    kafka_topic = 's1',
    partitions = 1,
    value_format = 'avro'
);

CREATE STREAM s2 AS
    SELECT 
        a, 
        formula_simple_log4j_logging(b, c) AS x,
        formula_custom_log4j_logging_level(b, c) AS y,
        formula_custom_logger(b, c) AS z
    FROM s1
    EMIT CHANGES;

INSERT INTO s1 (a, b, c) VALUES ('k1', 2, 3);
INSERT INTO s1 (a, b, c) VALUES ('k2', 4, 6);
INSERT INTO s1 (a, b, c) VALUES ('k3', 6, 9);
EOF

sleep 10

log "Verify the UDF logs using KSQL SLF4J+Log4j1 logger and default log level..."
docker container logs ksqldb-server 2>/dev/null | grep -E "INFO V1: \d+, V2: \d+ \(com\.example\.FormulaUdfSimpleLog4jLogging)"

log "Verify the UDF logs using KSQL SLF4J+Log4j1 logger and custom log level..."
docker exec ksqldb-server cat /etc/ksqldb-server/log4j.properties | grep "FormulaUdfLog4jCustomLoggingLevel"
docker container logs ksqldb-server 2>/dev/null | grep -E "DEBUG V1: \d+, V2: \d+ \(com\.example\.FormulaUdfLog4jCustomLoggingLevel\)"

log "Verify the UDF logs using a custom SLF4J+Logback logger, custom log level and custom message format..."
docker container logs ksqldb-server 2>/dev/null | grep -E "INFO  com\.example\.FormulaUdfCustomLogger - V1: \d+, V2: \d+"
