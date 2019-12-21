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

ZOOKEEPER_IP=$(container_to_ip zookeeper)
interface=eth0

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

echo -e "\033[0;33mBlocking communication between jms-client and zookeeper\033[0m"
block_host jms-client $ZOOKEEPER_IP

echo -e "\033[0;33mSending messages to topic test-queue using JMS client\033[0m"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e ZOOKEEPER_CONNECT="zookeeper:2181" -e USERNAME="client" -e PASSWORD="client-secret" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

echo -e "\033[0;33mRemoving network partition between jms-client and zookeeper\033[0m"
remove_partition jms-client zookeeper

# [2019-12-21 11:39:07,442] INFO Opening socket connection to server zookeeper.sasl-ssl_default/192.168.160.2:2181. Will not attempt to authenticate using SASL (unknown error) (org.apache.zookeeper.ClientCnxn)
# [2019-12-21 11:39:10,640] WARN Session 0x0 for server null, unexpected error, closing socket connection and attempting reconnect (org.apache.zookeeper.ClientCnxn)
# java.net.NoRouteToHostException: No route to host
#         at sun.nio.ch.SocketChannelImpl.checkConnect(Native Method)
#         at sun.nio.ch.SocketChannelImpl.finishConnect(SocketChannelImpl.java:717)
#         at org.apache.zookeeper.ClientCnxnSocketNIO.doTransport(ClientCnxnSocketNIO.java:361)
#         at org.apache.zookeeper.ClientCnxn$SendThread.run(ClientCnxn.java:1141)
# [2019-12-21 11:39:11,715] INFO Opening socket connection to server zookeeper.sasl-ssl_default/192.168.160.2:2181. Will not attempt to authenticate using SASL (unknown error) (org.apache.zookeeper.ClientCnxn)
# [2019-12-21 11:39:13,720] WARN Session 0x0 for server null, unexpected error, closing socket connection and attempting reconnect (org.apache.zookeeper.ClientCnxn)
# java.net.NoRouteToHostException: No route to host
#         at sun.nio.ch.SocketChannelImpl.checkConnect(Native Method)
#         at sun.nio.ch.SocketChannelImpl.finishConnect(SocketChannelImpl.java:717)
#         at org.apache.zookeeper.ClientCnxnSocketNIO.doTransport(ClientCnxnSocketNIO.java:361)
#         at org.apache.zookeeper.ClientCnxn$SendThread.run(ClientCnxn.java:1141)
# [2019-12-21 11:39:14,438] INFO Terminate ZkClient event thread. (org.I0Itec.zkclient.ZkEventThread)
# [2019-12-21 11:39:14,822] INFO Opening socket connection to server zookeeper.sasl-ssl_default/192.168.160.2:2181. Will not attempt to authenticate using SASL (unknown error) (org.apache.zookeeper.ClientCnxn)
# [2019-12-21 11:39:16,948] INFO Session: 0x0 closed (org.apache.zookeeper.ZooKeeper)
# Exception in thread "main" org.I0Itec.zkclient.exception.ZkTimeoutException: Unable to connect to zookeeper server 'zookeeper:2181' with timeout of 7000 ms
#         at org.I0Itec.zkclient.ZkClient.connect(ZkClient.java:1233)
#         at org.I0Itec.zkclient.ZkClient.<init>(ZkClient.java:157)
#         at org.I0Itec.zkclient.ZkClient.<init>(ZkClient.java:131)
#         at kafka.utils.ZkUtils$.createZkClientAndConnection(ZkUtils.scala:95)
#         at kafka.utils.ZkUtils$.apply(ZkUtils.scala:77)
# [2019-12-21 11:39:16,951] INFO EventThread shut down for session: 0x0 (org.apache.zookeeper.ClientCnxn)
#         at kafka.utils.ZkUtils.apply(ZkUtils.scala)
#         at io.confluent.kafka.jms.ZkTrialPeriod.startOrVerify(ZkTrialPeriod.java:38)
#         at io.confluent.kafka.jms.DefaultLicenseValidator.validateTrialPeriod(DefaultLicenseValidator.java:63)
#         at io.confluent.kafka.jms.KafkaConnectionFactory.validateLicense(KafkaConnectionFactory.java:81)
#         at io.confluent.kafka.jms.KafkaConnectionFactory.createConnection(KafkaConnectionFactory.java:109)
#         at com.github.vdesabou.App.main(App.java:39)
