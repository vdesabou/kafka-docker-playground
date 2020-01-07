#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"


rm -f ${DIR}/broker/logs/*
rm -f ${DIR}/zookeeper/logs/*
rm -f ${DIR}/connect/logs/*
rm -f ${DIR}/schema-registry/logs/*
rm -f ${DIR}/control-center/logs/*
rm -f ${DIR}/ksql-server/logs/*

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml" -a
