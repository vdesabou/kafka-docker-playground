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

# make sure to run HA_PROXY on an EC2 instance

# to block traffic from one of the brokers, here is an example
# nslookup b0-pkc-r5djp.europe-west1.gcp.confluent.cloud                                                      Server:         172.31.0.2
# Address:        172.31.0.2#53

# Non-authoritative answer:
# Name:   b0-pkc-r5djp.europe-west1.gcp.confluent.cloud
# Address: 34.78.32.173

# docker exec --privileged --user root -i haproxy bash -c 'iptables -A INPUT -p tcp -s 34.78.32.173 -j DROP'
# docker exec --privileged --user root -i haproxy bash -c 'iptables -D INPUT -p tcp -s 34.78.32.173 -j DROP'


function update_hosts_file() {

    docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP client sh -c 'echo "$HAPROXY_IP $PKC_ENDPOINT" >> /etc/hosts'
    for (( i=0; i<$nb_broker; i++ ))
    do
        docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP -e i=$i client sh -c 'echo "$HAPROXY_IP b$i-$PKC_ENDPOINT" >> /etc/hosts'
    done

    docker exec -i client sh -c 'cat /etc/hosts'
}

PKC_ENDPOINT=${PKC_ENDPOINT:-$1}
CLOUD_KEY=${CLOUD_KEY:-$2}
CLOUD_SECRET=${CLOUD_SECRET:-$3}
HAPROXY_IP=${HAPROXY_IP:-$4}

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

if [ -z "$HAPROXY_IP" ]
then
     logerror "HAPROXY_IP is not set. Export it as environment variable or pass it as argument"
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

# generate producer.js
sed -e "s|:BOOTSTRAP_SERVERS:|$PKC_ENDPOINT_WITH_PORT|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/producer-template-repro-timeout-aws.js > ${DIR}/producer.js
# generate consumer.js
sed -e "s|:BOOTSTRAP_SERVERS:|$PKC_ENDPOINT_WITH_PORT|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/consumer-template.js > ${DIR}/consumer.js


docker-compose -f "${PWD}/docker-compose-repro-timeout-aws.yml" down
docker-compose -f "${PWD}/docker-compose-repro-timeout-aws.yml" build
docker-compose -f "${PWD}/docker-compose-repro-timeout-aws.yml" up -d

log "Update host file"
update_hosts_file

log "Starting consumer"
docker exec -i client node /usr/src/app/consumer.js > consumer.log 2>&1 &

log "Starting producer"
docker exec -i client node /usr/src/app/producer.js > producer.log 2>&1 &

exit 0
