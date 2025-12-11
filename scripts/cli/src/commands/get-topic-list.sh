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