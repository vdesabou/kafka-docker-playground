#!/bin/bash

get_kafka_cluster_id_from_container()
{
  KAFKA_CLUSTER_ID=$(docker container exec zookeeper zookeeper-shell zookeeper:2181 get /cluster/id 2> /dev/null | grep \"version\" | jq -r .id)
  #KAFKA_CLUSTER_ID=$(curl -s http://localhost:8091/v1/metadata/id  | jq -r ".id")
  if [ -z "$KAFKA_CLUSTER_ID" ]; then
    echo "Failed to retrieve Kafka cluster id from ZooKeeper"
    exit 1
  fi
  echo $KAFKA_CLUSTER_ID
  return 0
}

mds_login()
{
  MDS_URL=$1
  SUPER_USER=$2
  SUPER_USER_PASSWORD=$3

  # Log into MDS
  if [[ $(type expect 2>&1) =~ "not found" ]]; then
    echo "'expect' is not found. Install 'expect' and try again"
    exit 1
  fi
  echo -e "\n# Login to MDS using Confluent CLI"
  OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url $MDS_URL
    expect "Username: "
    send "${SUPER_USER}\r";
    expect "Password: "
    send "${SUPER_USER_PASSWORD}\r";
    expect EOF
    catch wait result
    exit [lindex \$result 3]
END
  )
  if [ $? -ne 0 ]; then
    echo "Failed to log into MDS. Please check all parameters and run again."
    exit
  fi
}