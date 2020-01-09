#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

interface=eth0


container_to_ip() {
    name=$1
    echo $(docker exec $name hostname -I)
}

block_host() {
    name=$1
    shift 1

    # https://serverfault.com/a/906499
    docker exec --privileged -t $name bash -c "tc qdisc add dev $interface root handle 1: prio" 2>&1

    for ip in $@; do
        docker exec --privileged -t $name bash -c "tc filter add dev $interface protocol ip parent 1: prio 1 u32 match ip dst $ip flowid 1:1" 2>&1
    done

    docker exec --privileged -t $name bash -c "tc filter add dev $interface protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2" 2>&1
    docker exec --privileged -t $name bash -c "tc filter add dev $interface protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2" 2>&1
    docker exec --privileged -t $name bash -c "tc qdisc add dev $interface parent 1:1 handle 10: netem loss 100%" 2>&1
    docker exec --privileged -t $name bash -c "tc qdisc add dev $interface parent 1:2 handle 20: sfq" 2>&1
}


remove_partition() {
    for name in $@; do
        docker exec --privileged -t $name bash -c "tc qdisc del dev $interface root" 2>&1 > /dev/null
    done
}

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b
interface=eth0
ZOOKEEPER_IP=$(container_to_ip zookeeper)

log "Blocking communication between jms-client and zookeeper"
block_host jms-client $ZOOKEEPER_IP

log "Sending messages to topic test-queue using JMS client"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e USERNAME="client" -e PASSWORD="client-secret" -e CONFLUENT_LICENSE="put your license here" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

log "Removing network partition between jms-client and zookeeper"
remove_partition jms-client zookeeper
