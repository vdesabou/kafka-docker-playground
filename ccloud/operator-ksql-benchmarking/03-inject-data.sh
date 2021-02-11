#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

if [ -r ${DIR}/ccloud-cluster.properties ]
then
    . ${DIR}/ccloud-cluster.properties
else
    logerror "Cannot read configuration file ${APP_HOME}/ccloud-cluster.properties"
    exit 1
fi

verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

# TODO change file based on k8s cluster
# Use most basic values file and override it with --set
VALUES_FILE="${DIR}/../../operator/private.yaml"
CONFIG_FILE=${DIR}/client.properties

cat << EOF > ${CONFIG_FILE}
bootstrap.servers=${bootstrap_servers}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${cluster_api_key}' password='${cluster_api_secret}';
schema.registry.url=${schema_registry_url}
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${schema_registry_api_key}:${schema_registry_api_secret}
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
EOF

#######
# INJECTING DATA
#######
# FIXTHIS shipments customers products

for topic in orders
do
  log "Creating ${topic}"
  set +e
  log "Create topic ${topic}"
  kubectl cp ${CONFIG_FILE} confluent/connectors-0:/tmp/config
  kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ${topic} --delete
  kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ${topic} --create --replication-factor 3 --partitions ${number_topic_partitions}
  kubectl exec -i connectors-0 -- curl -X DELETE http://localhost:8083/connectors/datagen-${topic}
  set -e

  ITERATIONS=$(eval echo '$'${topic}_iterations)
  # https://github.com/confluentinc/kafka-connect-datagen#configuration
  kubectl exec -i connectors-0 -- curl -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "'"$topic"'",
                "quickstart": "'"$topic"'",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 10,
                "iterations": "'"$ITERATIONS"'",
                "tasks.max": "'"$datagen_tasks"'"
            }' \
      http://localhost:8083/connectors/datagen-${topic}/config | jq


  set +e
  # wait for all tasks to be FAILED with org.apache.kafka.connect.errors.ConnectException: Stopping connector: generated the configured xxx number of messages
  #   {
  #   "id": 9,
  #   "state": "FAILED",
  #   "worker_id": "connectors-0.connectors.confluent.svc.cluster.local:9083",
  #   "trace": "org.apache.kafka.connect.errors.ConnectException: Stopping connector: generated the configured 100 number of messages\n\tat io.confluent.kafka.connect.datagen.DatagenTask.poll(DatagenTask.java:238)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:289)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:256)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:834)\n"
  # }
  MAX_WAIT=480
  CUR_WAIT=0
  log "Waiting up to $MAX_WAIT seconds for topic $topic to be filled with $ITERATIONS records"
  kubectl exec -i connectors-0 -- curl -s -X GET http://localhost:8083/connectors/datagen-${topic}/status | jq .tasks[].trace | grep "generated the configured" | wc -l > /tmp/out.txt 2>&1
  while [[ ! $(cat /tmp/out.txt) =~ "$datagen_tasks" ]]; do
    sleep 10
    kubectl exec -i connectors-0 -- curl -s -X GET http://localhost:8083/connectors/datagen-${topic}/status | jq .tasks[].trace | grep "generated the configured" | wc -l > /tmp/out.txt 2>&1
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: Please troubleshoot'.\n"
      kubectl exec -i connectors-0 -- curl -s -X GET http://localhost:8083/connectors/datagen-${topic}/status | jq
      rm ${CONFIG_FILE}
      exit 1
    fi
  done
  log "Topic $topic is now filled with $ITERATIONS records"
  set -e
done

log "Verify we have received data in topic ${topic}"
kubectl exec -it connectors-0 -- kafka-console-consumer --topic ${topic} --bootstrap-server ${bootstrap_servers} --consumer.config /tmp/config --from-beginning --max-messages 2

rm ${CONFIG_FILE}