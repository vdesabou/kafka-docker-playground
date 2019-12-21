#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

interface=eth0


container_to_ip() {
    name=$1
    echo $(docker exec $name hostname -I)
}

block_host() {
    name=$1
    shift 1
    docker exec --privileged -t $name bash -c "tc qdisc add dev $interface root handle 1: prio" 2>&1
    docker exec --privileged -t $name bash -c "tc qdisc add dev $interface parent 1:1 handle 2: netem loss 100%" 2>&1
    for ip in $@; do
        docker exec --privileged -t $name bash -c "tc filter add dev $interface parent 1:0 protocol ip prio 1 u32 match ip dst $ip flowid 2:1" 2>&1
    done
}

remove_partition() {
	for name in $@; do
		docker exec --privileged -t $name bash -c "tc qdisc del dev $interface root" 2>&1 > /dev/null
	done
}

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

interface=eth0
ZOOKEEPER_IP=$(container_to_ip zookeeper)
JMS_CLIENT_IP=$(container_to_ip jms-client)

echo -e "\033[0;33mBlocking communication between jms-client and zookeeper\033[0m"
block_host jms-client $ZOOKEEPER_IP
block_host zookeeper $JMS_CLIENT_IP

echo -e "\033[0;33mSending messages to topic test-queue using JMS client\033[0m"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e USERNAME="client" -e PASSWORD="client-secret" -e CONFLUENT_LICENSE="put your license here" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

echo -e "\033[0;33mRemoving network partition between jms-client and zookeeper\033[0m"
remove_partition jms-client zookeeper
