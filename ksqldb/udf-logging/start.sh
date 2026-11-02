#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/udf-simple-logging/target/udf-simple-logging-1.0.0.jar ]
then
    log "Building udf-simple-logging jar"
    build_java_component_with_retry "udf-simple-logging" docker run -i --rm -v "${DIR}/udf-simple-logging":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/udf-simple-logging/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml package
fi

if [ ! -f ${DIR}/udf-custom-logger/target/udf-custom-logger-1.0.0-jar-with-dependencies.jar ]
then
    log "Building udf-custom-logger jar"
    build_java_component_with_retry "udf-custom-logger" docker run -i --rm -v "${DIR}/udf-custom-logger":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/udf-custom-logger/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml package
fi

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating streams with UDF and inserting data..."
playground ksqldb sql << EOF
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

playground ksqldb wait

log "Verify the UDF logs using KSQL SLF4J+Log4j1 logger and default log level..."
playground container logs -c ksqldb-server --no-follow --grep "INFO V1: [0-9]*, V2: [0-9]* (com.example.FormulaUdfSimpleLog4jLogging)"

log "Verify the UDF logs using KSQL SLF4J+Log4j1 logger and custom log level..."
playground container exec -c ksqldb-server --command "grep FormulaUdfLog4jCustomLoggingLevel /etc/ksqldb-server/log4j.properties"
playground container logs -c ksqldb-server --no-follow --grep "DEBUG V1: [0-9]*, V2: [0-9]* (com.example.FormulaUdfLog4jCustomLoggingLevel)"

log "Verify the UDF logs using a custom SLF4J+Logback logger, custom log level and custom message format..."
playground container logs -c ksqldb-server --no-follow --grep "INFO  com.example.FormulaUdfCustomLogger - V1: [0-9]*, V2: [0-9]*"
