#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8
then
    log "📝 CP 8+ (log4j2): Kafka appender of log4j-core, configured in log4j2-plaintext.yaml"
    DOCKER_COMPOSE_OVERRIDE_FILE="${PWD}/docker-compose.plaintext.yml"
else
    log "📝 CP 7 (log4j 1): KafkaLog4jAppender, configured in log4j-plaintext.properties"
    # the kafka-log4j-appender jar is not in the cp-server-connect image
    KAFKA_LOG4J_APPENDER_VERSION="3.9.1"
    if [ ! -f "${DIR}/kafka-log4j-appender.jar" ]
    then
        log "⬇️ Downloading kafka-log4j-appender ${KAFKA_LOG4J_APPENDER_VERSION} from Maven Central"
        curl -sSfL -o "${DIR}/kafka-log4j-appender.jar" "https://repo1.maven.org/maven2/org/apache/kafka/kafka-log4j-appender/${KAFKA_LOG4J_APPENDER_VERSION}/kafka-log4j-appender-${KAFKA_LOG4J_APPENDER_VERSION}.jar"
    fi
    DOCKER_COMPOSE_OVERRIDE_FILE="${PWD}/docker-compose.plaintext.log4j1.yml"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${DOCKER_COMPOSE_OVERRIDE_FILE}"

log "Waiting for the Connect logs in topic connect-logs"
playground topic wait-for-records --topic connect-logs --min-expected-messages 10 --max-wait 120

log "Checking that the worker startup log is in topic connect-logs"
playground topic consume --topic connect-logs --grep "Kafka Connect started" --max-messages 1
