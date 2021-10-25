#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

REST_KEY=${REST_KEY:-$1}
REST_SECRET=${REST_SECRET:-$2}

if [ -z "$REST_KEY" ]
then
     logerror "REST_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$REST_SECRET" ]
then
     logerror "REST_SECRET is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../ccloud-demo/ccloud-generate-env-vars.sh ${CONFIG_FILE}

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

# generate kafka-admin.properties config
sed -e "s|:REST_KEY:|$REST_KEY|g" \
    -e "s|:REST_SECRET:|$REST_SECRET|g" \
    ${DIR}/kafka-rest.jaas-template.conf > ${DIR}/kafka-rest.jaas.conf

cd ${DIR}/security
log "🔐 Generate keys and certificates used for SSL"
./certs-create.sh $REST_KEY > /dev/null 2>&1
if [ -z "$CI" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
cd ${DIR}

docker-compose -f "${PWD}/docker-compose.yml" up -d

log "Creating topic rest-proxy-security-plugin in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic rest-proxy-security-plugin
set -e

sleep 15

# run as root for linux case where key is owned by root user
log "HTTP client using $REST_KEY principal"
docker exec -e REST_KEY=$REST_KEY --privileged --user root restproxy curl -X POST --cert /etc/kafka/secrets/$REST_KEY.certificate.pem --key /etc/kafka/secrets/$REST_KEY.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "https://localhost:8082/topics/rest-proxy-security-plugin"
