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

echo -e "\033[0;33mBlocking communication between jms-client and zookeeper\033[0m"
block_host jms-client $ZOOKEEPER_IP

echo -e "\033[0;33mSending messages to topic test-queue using JMS client\033[0m"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e USERNAME="client" -e PASSWORD="client-secret" -e CONFLUENT_LICENSE="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ2aW5jZW50X2RlX3NhYm91bGluIiwiZXhwIjoxNjEwMzIzMjAwLCJpYXQiOjE1NDcxNjQ4MDAsImlzcyI6IkNvbmZsdWVudCIsIm1vbml0b3JpbmciOnRydWUsIm5iNCI6MTU3MzA1ODA0OCwic3ViIjoiY29udHJvbC1jZW50ZXIifQ.Om532E5DYdWd9Fw0_0hJvWvmVpcHlTxbZWQeozjJkDsTg45iqwN2mCT3ULyoyTV28z9qCn8YwEwyMFzwzzFRDSXpeWrTwnzrFjZfF00tZdw70-IEA7skpZ1PI5chS-Zdq20apxiWkIJR1qNRRwlapzKlPj7Um7UkPwmwLPK5cjIv7B-o01DtgqVgeGt_VMDBEJUcGcUa92ntawgI3x5y6BLpNbe246WrtjcA_I0URDwT64j6xvN2erNiC90Bu0zX8OM-g09Nac3p5Rg1HVdXdDSYOOy6_74qgB8t-7J5RHKuF2SiZI-kIFLU_wG-9-ECVMBsQNSr9a8k5z2-A-5NwA
" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

echo -e "\033[0;33mRemoving network partition between jms-client and zookeeper\033[0m"
remove_partition jms-client zookeeper
