skip_connect_internal_topics="${args[--skip-connect-internal-topics]}"

get_environment_used

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

if [[ "$environment" == "environment" ]]
then
  set +e
  confluent kafka topic list | awk '{if(NR>2) print $1}'
  set -e
else
  # trick to be faster
  docker exec broker ls /var/lib/kafka/data > /dev/null 2>&1
  if [ $? -eq 0 ]
  then
    if [[ -n "$skip_connect_internal_topics" ]]
    then
      docker exec broker ls /var/lib/kafka/data | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "connect-" | grep -v "^_" | grep -v "delete" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
    else
      docker exec broker ls /var/lib/kafka/data | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "^_" | grep -v "delete" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
    fi
  fi
fi