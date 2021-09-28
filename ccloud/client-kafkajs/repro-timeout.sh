#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function generate_haproxy_config() {
    TMP_FILE=${DIR}/haproxy/haproxy_tmp.cfg
    rm -f ${TMP_FILE}

    echo " " >> $TMP_FILE
    echo "    # define acl depending certificate name" >> $TMP_FILE
    echo "    acl is_bootstrap req.ssl_sni -i $PKC_ENDPOINT" >> $TMP_FILE
    for (( i=0; i<$nb_broker; i++ ))
    do
        echo "    acl is_kafka$i req.ssl_sni -i b$i-$PKC_ENDPOINT" >> $TMP_FILE
    done

    if [ ! -z "$PKAC_ENDPOINT" ]
    then
        echo "    acl is_topic req.ssl_sni -i $PKAC_ENDPOINT" >> $TMP_FILE
    fi

    if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
    then
        echo "    acl is_ccsr req.ssl_sni -i $SCHEMA_REGISTRY_ENDPOINT" >> $TMP_FILE
    fi

    echo " " >> $TMP_FILE

    echo "    # depending name rule to route to specified backend" >> $TMP_FILE
    echo "    use_backend bootstrap if is_bootstrap" >> $TMP_FILE
    for (( i=0; i<$nb_broker; i++ ))
    do
        echo "    use_backend kafka$i if is_kafka$i" >> $TMP_FILE
    done

    if [ ! -z "$PKAC_ENDPOINT" ]
    then
        echo "    use_backend topic if is_topic" >> $TMP_FILE
    fi

    if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
    then
        echo "    use_backend ccsr if is_ccsr" >> $TMP_FILE
    fi

    echo " " >> $TMP_FILE
    echo "# backend definitions" >> $TMP_FILE
    echo "backend bootstrap" >> $TMP_FILE
    echo "    mode tcp" >> $TMP_FILE
    echo "    server bootstrap $PKC_ENDPOINT_WITH_PORT check" >> $TMP_FILE
    for (( i=0; i<$nb_broker; i++ ))
    do
        echo "backend kafka$i" >> $TMP_FILE
        echo "    mode tcp" >> $TMP_FILE
        echo "    server kafka$i b$i-$PKC_ENDPOINT_WITH_PORT check" >> $TMP_FILE
    done
    echo " " >> $TMP_FILE

    if [ ! -z "$PKAC_ENDPOINT" ]
    then
        echo "backend topic" >> $TMP_FILE
        echo "    mode tcp" >> $TMP_FILE
        echo "    server topic $PKAC_ENDPOINT:443 check" >> $TMP_FILE
    fi

    if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
    then
        echo "backend ccsr" >> $TMP_FILE
        echo "    mode tcp" >> $TMP_FILE
        echo "    server ccsr $SCHEMA_REGISTRY_ENDPOINT:443 check" >> $TMP_FILE
    fi

    rm -f ${DIR}/haproxy/haproxy.cfg
    cat ${DIR}/haproxy/haproxy-template.cfg $TMP_FILE >> ${DIR}/haproxy/haproxy.cfg
}

function update_hosts_file() {
    HAPROXY_IP=$(container_to_ip haproxy)
    docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP client sh -c 'echo "$HAPROXY_IP $PKC_ENDPOINT" >> /etc/hosts'
    for (( i=0; i<$nb_broker; i++ ))
    do
        docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP -e i=$i client sh -c 'echo "$HAPROXY_IP b$i-$PKC_ENDPOINT" >> /etc/hosts'
    done
    if [ ! -z "$PKAC_ENDPOINT" ]
    then
        docker exec -i -e PKAC_ENDPOINT=$PKAC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP client sh -c 'echo "$HAPROXY_IP $PKAC_ENDPOINT" >> /etc/hosts'
    fi
    if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
    then
        docker exec -i -e SCHEMA_REGISTRY_ENDPOINT=$SCHEMA_REGISTRY_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP client sh -c 'echo "$HAPROXY_IP $SCHEMA_REGISTRY_ENDPOINT" >> /etc/hosts'
    fi
    docker exec -i client sh -c 'cat /etc/hosts'
}


PKC_ENDPOINT=${PKC_ENDPOINT:-$1}
CLOUD_KEY=${CLOUD_KEY:-$2}
CLOUD_SECRET=${CLOUD_SECRET:-$3}

if [ -z "$PKC_ENDPOINT" ]
then
     logerror "PKC_ENDPOINT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$PKC_ENDPOINT" = *2 ]]
then
    logerror "PKC_ENDPOINT is the pkc endpoint without ':9092'"
    exit 1
fi

if [ -z "$CLOUD_KEY" ]
then
     logerror "CLOUD_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$CLOUD_SECRET" ]
then
     logerror "CLOUD_SECRET is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

PKC_ENDPOINT_WITH_PORT="$PKC_ENDPOINT:9092"

log "Checking with Kafkacat before using HAProxy"
docker run confluentinc/cp-kafkacat:${TAG} kafkacat -b $PKC_ENDPOINT_WITH_PORT -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "broker"

nb_broker=$(docker run confluentinc/cp-kafkacat:${TAG} kafkacat -b $PKC_ENDPOINT_WITH_PORT -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "pkc" | grep " at " | wc -l)
if [ $nb_broker -eq 0 ]
then
    logerror "ERROR: No broker could be discovered using Kafkacat"
    exit 1
fi

log "Generating haproxy.cfg file based on Kafkacat results"
generate_haproxy_config

docker-compose -f "${PWD}/docker-compose-repro-timeout.yml" down
docker-compose -f "${PWD}/docker-compose-repro-timeout.yml" build
docker-compose -f "${PWD}/docker-compose-repro-timeout.yml" up -d

log "Updating /etc/hosts on client container, so that HAProxy is used"
update_hosts_file

# generate producer.js
sed -e "s|:BOOTSTRAP_SERVERS:|$PKC_ENDPOINT_WITH_PORT|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/producer-template-repro-timeout.js > ${DIR}/producer.js
# generate consumer.js
sed -e "s|:BOOTSTRAP_SERVERS:|$PKC_ENDPOINT_WITH_PORT|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/consumer-template.js > ${DIR}/consumer.js

log "Starting consumer"
docker exec -i client node /usr/src/app/consumer.js > consumer.log 2>&1 &

log "Starting producer"
docker exec -i client node /usr/src/app/producer.js > producer.log 2>&1 &

exit 0

date;docker exec --privileged --user root -i haproxy bash -c 'iptables -A INPUT -p tcp -s 35.205.238.172 -j DROP'
