skip_internal_topics="${args[--skip-internal-topics]}"

get_environment_used

if [[ "$environment" == "ccloud" ]]
then
  if [[ -n "$skip_internal_topics" ]]
  then
    set +e
    confluent kafka topic list | grep -v "connect-" | grep -v "_confluent-monitoring" | grep -v "_confluent-command" | awk '{if(NR>2) print $1}'
    set -e
  else
    set +e
    confluent kafka topic list | awk '{if(NR>2) print $1}'
    set -e
  fi
elif [[ "$environment" == "cfk" ]]
then
  set +e
  kafka_pod=$(resolve_container_name_for_environment "kafka")
  # Same speed trick as docker: list broker data dir directly.
  kubectl -n confluent exec "$kafka_pod" -- ls /mnt/data/data0/logs > /dev/null 2>&1
  if [[ $? -eq 0 ]]
  then
    if [[ -n "$skip_internal_topics" ]]
    then
      kubectl -n confluent exec "$kafka_pod" -- ls /mnt/data/data0/logs 2>/dev/null | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "connect-" | grep -v "^_" | grep -v "delete" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
    else
      kubectl -n confluent exec "$kafka_pod" -- ls /mnt/data/data0/logs 2>/dev/null | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "delete" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
    fi
  else
    if [[ -n "$skip_internal_topics" ]]
    then
    kubectl -n confluent exec connect-0 -- kafka-topics --bootstrap-server kafka:9071 --list 2>/dev/null | grep -v "connect-" | grep -v "^_"
    else
    kubectl -n confluent exec connect-0 -- kafka-topics --bootstrap-server kafka:9071 --list 2>/dev/null
    fi
  fi
  set -e
else
  get_broker_container
  # trick to be faster
  docker exec $broker_container ls /var/lib/kafka/data > /dev/null 2>&1
  if [ $? -eq 0 ]
  then
    if [[ -n "$skip_internal_topics" ]]
    then
      docker exec $broker_container ls /var/lib/kafka/data | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "connect-" | grep -v "^_" | grep -v "delete" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
    else
      docker exec $broker_container ls /var/lib/kafka/data | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "delete" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
    fi
  fi
fi