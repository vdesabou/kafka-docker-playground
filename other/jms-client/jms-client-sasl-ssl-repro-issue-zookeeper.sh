#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

ZOOKEEPER_IP=$(container_to_ip zookeeper)

log "Blocking communication between jms-client and zookeeper"
block_host jms-client $ZOOKEEPER_IP

log "Sending messages to topic test-queue using JMS client"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e ZOOKEEPER_CONNECT="zookeeper:2181" -e USERNAME="client" -e PASSWORD="client-secret" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

log "Removing network partition between jms-client and zookeeper"
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
