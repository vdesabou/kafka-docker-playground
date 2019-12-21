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

JMSCLIENT_IP=$(container_to_ip jms-client)
interface=eth0

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

echo -e "\033[0;33mBlocking communication between jms-client and zookeeper\033[0m"
block_host zookeeper $JMSCLIENT_IP

echo -e "\033[0;33mSending messages to topic test-queue using JMS client\033[0m"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e ZOOKEEPER_CONNECT="zookeeper:2181" -e USERNAME="client" -e PASSWORD="client-secret" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

echo -e "\033[0;33mRemoving network partition between jms-client and zookeeper\033[0m"
remove_partition zookeeper jms-client

# [2019-12-21 11:18:58,261] INFO Waiting for keeper state SyncConnected (org.I0Itec.zkclient.ZkClient)
# [2019-12-21 11:18:58,265] INFO Opening socket connection to server zookeeper.sasl-ssl_default/192.168.128.2:2181. Will not attempt to authenticate using SASL (unknown error) (org.apache.zookeeper.ClientCnxn)
# [2019-12-21 11:19:05,263] INFO Terminate ZkClient event thread. (org.I0Itec.zkclient.ZkEventThread)
