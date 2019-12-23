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
        docker exec --privileged -t $name bash -c "tc qdisc del dev eth0 root" 2>&1 > /dev/null
    done
}

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

ZOOKEEPER_IP=$(container_to_ip zookeeper)
interface=eth0

echo -e "\033[0;33mBlocking communication between jms-client and zookeeper\033[0m"
block_host jms-client $ZOOKEEPER_IP

echo -e "\033[0;33mSending messages to topic test-queue using JMS client\033[0m"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e ZOOKEEPER_CONNECT="zookeeper:2181" -e USERNAME="client" -e PASSWORD="client-secret" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

echo -e "\033[0;33mRemoving network partition between jms-client and zookeeper\033[0m"
remove_partition jms-client zookeeper

# [2019-12-23 13:08:13,379] INFO Opening socket connection to server zookeeper.sasl-ssl_default/172.24.0.2:2181. Will not attempt to authenticate using SASL (unknown error) (org.apache.zookeeper.ClientCnxn)
# [2019-12-23 13:08:20,375] INFO Terminate ZkClient event thread. (org.I0Itec.zkclient.ZkEventThread)
# [2019-12-23 13:08:43,375] WARN Client session timed out, have not heard from server in 30001ms for sessionid 0x0 (org.apache.zookeeper.ClientCnxn)
# [2019-12-23 13:08:43,482] INFO Session: 0x0 closed (org.apache.zookeeper.ZooKeeper)
# Exception in thread "main" org.I0Itec.zkclient.exception.ZkTimeoutException: Unable to connect to zookeeper server 'zookeeper:2181' with timeout of 7000 ms[2019-12-23 13:08:43,486] INFO EventThread shut down for session: 0x0 (org.apache.zookeeper.ClientCnxn)

#         at org.I0Itec.zkclient.ZkClient.connect(ZkClient.java:1233)
#         at org.I0Itec.zkclient.ZkClient.<init>(ZkClient.java:157)
#         at org.I0Itec.zkclient.ZkClient.<init>(ZkClient.java:131)
#         at kafka.utils.ZkUtils$.createZkClientAndConnection(ZkUtils.scala:95)
#         at kafka.utils.ZkUtils$.apply(ZkUtils.scala:77)
#         at kafka.utils.ZkUtils.apply(ZkUtils.scala)
#         at io.confluent.kafka.jms.ZkTrialPeriod.startOrVerify(ZkTrialPeriod.java:38)
#         at io.confluent.kafka.jms.DefaultLicenseValidator.validateTrialPeriod(DefaultLicenseValidator.java:63)
#         at io.confluent.kafka.jms.KafkaConnectionFactory.validateLicense(KafkaConnectionFactory.java:81)
#         at io.confluent.kafka.jms.KafkaConnectionFactory.createConnection(KafkaConnectionFactory.java:109)
#         at com.github.vdesabou.App.main(App.java:47)
