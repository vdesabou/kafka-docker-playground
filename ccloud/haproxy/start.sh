#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function generate_haproxy_config() {
    TMP_FILE=${DIR}/haproxy/haproxy_tmp.cfg
    rm -f ${TMP_FILE}

    echo " " >> $TMP_FILE
    echo "    # define acl depending certificate name" >> $TMP_FILE
    echo "    acl is_bootstrap req.ssl_sni -i $BOOTSTRAP_SERVER" >> $TMP_FILE
    for (( i=0; i<$nb_broker; i++ ))
    do
        echo "    acl is_kafka$i req.ssl_sni -i b$i-$BOOTSTRAP_SERVER" >> $TMP_FILE
    done

    echo " " >> $TMP_FILE

    echo "    # depending name rule to route to specified backend" >> $TMP_FILE
    echo "    use_backend bootstrap if is_bootstrap" >> $TMP_FILE
    for (( i=0; i<$nb_broker; i++ ))
    do
        echo "    use_backend kafka$i if is_kafka$i" >> $TMP_FILE
    done

    echo " " >> $TMP_FILE
    echo "# backend definitions" >> $TMP_FILE
    echo "backend bootstrap" >> $TMP_FILE
    echo "    mode tcp" >> $TMP_FILE
    echo "    server bootstrap $BOOTSTRAP_SERVERS check" >> $TMP_FILE
    for (( i=0; i<$nb_broker; i++ ))
    do
        echo "backend kafka$i" >> $TMP_FILE
        echo "    mode tcp" >> $TMP_FILE
        echo "    server kafka$i b$i-$BOOTSTRAP_SERVERS check" >> $TMP_FILE
    done
    echo " " >> $TMP_FILE

    rm -f ${DIR}/haproxy/haproxy.cfg
    cat ${DIR}/haproxy/haproxy-template.cfg $TMP_FILE >> ${DIR}/haproxy/haproxy.cfg
}

BOOTSTRAP_SERVER=${BOOTSTRAP_SERVER:-$1}
CLOUD_KEY=${CLOUD_KEY:-$2}
CLOUD_SECRET=${CLOUD_SECRET:-$3}

if [ -z "$BOOTSTRAP_SERVER" ]
then
     logerror "BOOTSTRAP_SERVER is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$BOOTSTRAP_SERVER" = *2 ]]
then
    logerror "BOOTSTRAP_SERVER is the pkc endpoint without ':9092'"
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

BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVER:9092"

log "Checking with Kafkacat before using HAProxy"
docker run confluentinc/cp-kafkacat:${TAG} kafkacat -b $BOOTSTRAP_SERVERS -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "broker"

nb_broker=$(docker run confluentinc/cp-kafkacat:${TAG} kafkacat -b $BOOTSTRAP_SERVERS -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "pkc" | grep " at " | wc -l)
if [ $nb_broker -eq 0 ]
then
    logerror "ERROR: No broker could be discovered using Kafkacat"
    exit 1
fi

log "Generating haproxy file based on Kafkacat results"
generate_haproxy_config

docker-compose -f "${PWD}/docker-compose.yml" down
docker-compose -f "${PWD}/docker-compose.yml" build
docker-compose -f "${PWD}/docker-compose.yml" up -d

log "Using iptables on client to block $BOOTSTRAP_SERVER and all broker IPs"
for ip in $(docker exec -i -e BOOTSTRAP_SERVER=$BOOTSTRAP_SERVER client bash -c 'nslookup $BOOTSTRAP_SERVER | grep Address | grep -v "#" | cut -d " " -f 2')
do
    log "Blocking IP address $ip corresponding to bootstrap server $BOOTSTRAP_SERVER"
    docker exec -i -e ip=$ip client bash -c 'iptables -I INPUT -p tcp -s $ip -j DROP'
done
for (( i=0; i<$nb_broker; i++ ))
do
    BROKER="b$i-$BOOTSTRAP_SERVER"
    ip=$(docker exec -i -e BROKER=$BROKER client bash -c 'nslookup $BROKER | grep Address | grep -v "#" | cut -d " " -f 2')
    log "Blocking IP address $ip corresponding to broker $BROKER"
    docker exec -i -e ip=$ip client bash -c 'iptables -I INPUT -p tcp -s $ip -j DROP'
done

log "Verify it is no more working, as expected"
set +e
docker exec -i -e BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS -e CLOUD_KEY=$CLOUD_KEY -e CLOUD_SECRET=$CLOUD_SECRET client bash -c 'kafkacat -b $BOOTSTRAP_SERVERS -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "broker"'
set -e

log "Modifying /etc/hosts on client container, so that haproxy is used"
HAPROXY_IP=$(container_to_ip haproxy)
docker exec -i -e BOOTSTRAP_SERVER=$BOOTSTRAP_SERVER -e HAPROXY_IP=$HAPROXY_IP client bash -c 'echo "$HAPROXY_IP $BOOTSTRAP_SERVER" >> /etc/hosts'
for (( i=0; i<$nb_broker; i++ ))
do
    docker exec -i -e BOOTSTRAP_SERVER=$BOOTSTRAP_SERVER -e HAPROXY_IP=$HAPROXY_IP -e i=$i client bash -c 'echo "$HAPROXY_IP b$i-$BOOTSTRAP_SERVER" >> /etc/hosts'
done
docker exec -i client bash -c 'cat /etc/hosts'

log "Verifying we can connect to $BOOTSTRAP_SERVER using HAProxy and netcat"
docker exec -i -e BOOTSTRAP_SERVER=$BOOTSTRAP_SERVER client bash -c 'nc -zv $BOOTSTRAP_SERVER 9092'

log "Verifying we can connect to $BOOTSTRAP_SERVERS using openssl"
# to get a tcpdump, run on client the following: tcpdump -w tcpdump.pcap -i eth0 -s 0 port 9092
docker exec -i -e BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS client bash -c 'echo QUIT | openssl s_client -connect $BOOTSTRAP_SERVERS'

log "Verifying we can use Kafkacat using HAProxy"
docker exec -i -e BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS -e CLOUD_KEY=$CLOUD_KEY -e CLOUD_SECRET=$CLOUD_SECRET client bash -c 'kafkacat -b $BOOTSTRAP_SERVERS -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "broker"'