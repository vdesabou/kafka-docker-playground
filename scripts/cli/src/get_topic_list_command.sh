skip_connect_internal_topics="${args[--skip-connect-internal-topics]}"

# trick to be faster
docker exec broker ls /var/lib/kafka/data > /dev/null 2>&1
if [ $? -eq 0 ]
then
  if [[ -n "$skip_connect_internal_topics" ]]
  then
    docker exec broker ls /var/lib/kafka/data | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "connect-" | grep -v "^_" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
  else
    docker exec broker ls /var/lib/kafka/data | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "^_" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq
  fi
fi