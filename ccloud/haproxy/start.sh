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

function block_traffic_for_all_endpoints() {
    log "Using iptables on client to block $PKC_ENDPOINT and all broker IPs"
    for ip in $(docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT client bash -c 'nslookup $PKC_ENDPOINT | grep Address | grep -v "#" | cut -d " " -f 2')
    do
        log "Blocking IP address $ip corresponding to bootstrap server $PKC_ENDPOINT"
        docker exec -i -e ip=$ip client bash -c 'iptables -I INPUT -p tcp -s $ip -j DROP'
    done
    for (( i=0; i<$nb_broker; i++ ))
    do
        BROKER="b$i-$PKC_ENDPOINT"
        ip=$(docker exec -i -e BROKER=$BROKER client bash -c 'nslookup $BROKER | grep Address | grep -v "#" | cut -d " " -f 2')
        log "Blocking IP address $ip corresponding to broker $BROKER"
        docker exec -i -e ip=$ip client bash -c 'iptables -I INPUT -p tcp -s $ip -j DROP'
    done

    if [ ! -z "$PKAC_ENDPOINT" ]
    then
        log "Using iptables on client to block $PKAC_ENDPOINT"
        for ip in $(docker exec -i -e PKAC_ENDPOINT=$PKAC_ENDPOINT client bash -c 'nslookup $PKAC_ENDPOINT | grep Address | grep -v "#" | cut -d " " -f 2')
        do
            log "Blocking IP address $ip corresponding to pkac endpoint $PKAC_ENDPOINT"
            docker exec -i -e ip=$ip client bash -c 'iptables -I INPUT -p tcp -s $ip -j DROP'
        done
    fi

    if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
    then
        log "Using iptables on client to block $SCHEMA_REGISTRY_ENDPOINT"
        for ip in $(docker exec -i -e SCHEMA_REGISTRY_ENDPOINT=$SCHEMA_REGISTRY_ENDPOINT client bash -c 'nslookup $SCHEMA_REGISTRY_ENDPOINT | grep Address | grep -v "#" | cut -d " " -f 2')
        do
            log "Blocking IP address $ip corresponding to psrc endpoint $SCHEMA_REGISTRY_ENDPOINT"
            docker exec -i -e ip=$ip client bash -c 'iptables -I INPUT -p tcp -s $ip -j DROP'
        done
    fi
}

function update_hosts_file() {
    HAPROXY_IP=$(container_to_ip haproxy)
    docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP client bash -c 'echo "$HAPROXY_IP $PKC_ENDPOINT" >> /etc/hosts'
    for (( i=0; i<$nb_broker; i++ ))
    do
        docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP -e i=$i client bash -c 'echo "$HAPROXY_IP b$i-$PKC_ENDPOINT" >> /etc/hosts'
    done
    if [ ! -z "$PKAC_ENDPOINT" ]
    then
        docker exec -i -e PKAC_ENDPOINT=$PKAC_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP client bash -c 'echo "$HAPROXY_IP $PKAC_ENDPOINT" >> /etc/hosts'
    fi
    if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
    then
        docker exec -i -e SCHEMA_REGISTRY_ENDPOINT=$SCHEMA_REGISTRY_ENDPOINT -e HAPROXY_IP=$HAPROXY_IP client bash -c 'echo "$HAPROXY_IP $SCHEMA_REGISTRY_ENDPOINT" >> /etc/hosts'
    fi
    docker exec -i client bash -c 'cat /etc/hosts'
}


PKC_ENDPOINT=${PKC_ENDPOINT:-$1}
CLOUD_KEY=${CLOUD_KEY:-$2}
CLOUD_SECRET=${CLOUD_SECRET:-$3}
PKAC_ENDPOINT=${PKAC_ENDPOINT:-$4}
SCHEMA_REGISTRY_ENDPOINT=${SCHEMA_REGISTRY_ENDPOINT:-$5}
SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=${SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:-$5}

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

if [ ! -z "$PKAC_ENDPOINT" ]
then
    if [[ "$PKAC_ENDPOINT" = https* ]]
    then
        logerror "PKAC_ENDPOINT should not include https:// part"
        exit 1
    fi
fi

if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
then
    if [[ "$SCHEMA_REGISTRY_ENDPOINT" = https* ]]
    then
        logerror "SCHEMA_REGISTRY_ENDPOINT should not include https:// part"
        exit 1
    fi

    if [ -z "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" ]
    then
        logerror "SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO is not set while SCHEMA_REGISTRY_ENDPOINT is set. Export it as environment variable or pass it as argument"
        exit 1
    fi
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

docker-compose -f "${PWD}/docker-compose.yml" down
docker-compose -f "${PWD}/docker-compose.yml" build
docker-compose -f "${PWD}/docker-compose.yml" up -d

log "Blocking traffic for all endpoints"
block_traffic_for_all_endpoints

log "Verify cluster is no more reachable using Kafkacat, as expected"
set +e
docker exec -i -e PKC_ENDPOINT_WITH_PORT=$PKC_ENDPOINT_WITH_PORT -e CLOUD_KEY=$CLOUD_KEY -e CLOUD_SECRET=$CLOUD_SECRET client bash -c 'kafkacat -b $PKC_ENDPOINT_WITH_PORT -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "broker"'
if [ ! -z "$PKAC_ENDPOINT" ]
then
    log "Verify pkac endpoint is no more reachable using curl, as expected"
    docker exec -i -e PKAC_ENDPOINT=$PKAC_ENDPOINT -e CLOUD_KEY=$CLOUD_KEY -e CLOUD_SECRET=$CLOUD_SECRET client bash -c 'curl --max-time 2 -u $CLOUD_KEY:$CLOUD_SECRET https://$PKAC_ENDPOINT/subjects'
fi
if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
then
    log "Verify Confluent Cloud Schema Registry is no more reachable using curl, as expected"
    docker exec -i -e SCHEMA_REGISTRY_ENDPOINT=$SCHEMA_REGISTRY_ENDPOINT -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO client bash -c 'curl --max-time 2 -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO https://$SCHEMA_REGISTRY_ENDPOINT/subjects'
fi
set -e

log "Updating /etc/hosts on client container, so that HAProxy is used"
update_hosts_file

log "Verifying we can connect to $PKC_ENDPOINT using HAProxy and netcat"
docker exec -i -e PKC_ENDPOINT=$PKC_ENDPOINT client bash -c 'nc -zv $PKC_ENDPOINT 9092'

log "Verifying we can connect to $PKC_ENDPOINT_WITH_PORT using openssl"
# to get a tcpdump, run on client the following: tcpdump -w tcpdump.pcap -i eth0 -s 0 port 9092
docker exec -i -e PKC_ENDPOINT_WITH_PORT=$PKC_ENDPOINT_WITH_PORT client bash -c 'echo QUIT | openssl s_client -connect $PKC_ENDPOINT_WITH_PORT'

log "Verifying we can use Kafkacat using HAProxy"
docker exec -i -e PKC_ENDPOINT_WITH_PORT=$PKC_ENDPOINT_WITH_PORT -e CLOUD_KEY=$CLOUD_KEY -e CLOUD_SECRET=$CLOUD_SECRET client bash -c 'kafkacat -b $PKC_ENDPOINT_WITH_PORT -L -X security.protocol=SASL_SSL -X sasl.mechanisms=PLAIN -X sasl.username=$CLOUD_KEY -X sasl.password=$CLOUD_SECRET | grep "broker"'

if [ ! -z "$PKAC_ENDPOINT" ]
then
    log "Verifying we can connect to pkac endpoint using HAProxy (HTTP 404 Not Found) is expected"
    docker exec -i -e PKAC_ENDPOINT=$PKAC_ENDPOINT -e CLOUD_KEY=$CLOUD_KEY -e CLOUD_SECRET=$CLOUD_SECRET client bash -c 'curl --max-time 2 -u $CLOUD_KEY:$CLOUD_SECRET https://$PKAC_ENDPOINT/subjects'

    log "Verifying we can connect to $PKAC_ENDPOINT using openssl"
    # to get a tcpdump, run on client the following: tcpdump -w tcpdump.pcap -i eth0 -s 0 port 9092
    docker exec -i -e PKAC_ENDPOINT=$PKAC_ENDPOINT client bash -c 'echo QUIT | openssl s_client -connect $PKAC_ENDPOINT:443'
fi

log "Verifying we can use Confluent Cloud Schema Registry using HAProxy"
if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ]
then
    docker exec -i -e SCHEMA_REGISTRY_ENDPOINT=$SCHEMA_REGISTRY_ENDPOINT -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO client bash -c 'curl --max-time 2 -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO https://$SCHEMA_REGISTRY_ENDPOINT/subjects'
fi