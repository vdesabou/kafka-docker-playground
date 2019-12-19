#!/bin/bash

IGNORE_CONNECT_STARTUP="FALSE"
IGNORE_CONTROL_CENTER_STARTUP="TRUE"

while getopts "h?ab" opt; do
    case "$opt" in
    h|\?)
        echo -e "\033[0;33mpossible options -a to ignore connect startup and -b to ignore control center\033[0m"
        exit 0
        ;;
    a)  IGNORE_CONNECT_STARTUP="TRUE"
        ;;
    b)  IGNORE_CONTROL_CENTER_STARTUP="TRUE"
        ;;
    esac
done


if [ "${IGNORE_CONNECT_STARTUP}" == "FALSE" ]
then
  # Verify Kafka Connect has started within MAX_WAIT seconds
  MAX_WAIT=120
  CUR_WAIT=0
  echo -e "\033[0;33mWaiting up to $MAX_WAIT seconds for Kafka Connect to start\033[0m"
  docker container logs connect > /tmp/out.txt 2>&1
  while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
    sleep 10
    docker container logs connect > /tmp/out.txt 2>&1
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: The logs in connect container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
      exit 1
    fi
  done
  echo -e "\033[0;33mConnect has started!\033[0m"
fi


if [ "${IGNORE_CONTROL_CENTER_STARTUP}" == "FALSE" ]
then
  # Verify Confluent Control Center has started within MAX_WAIT seconds
  MAX_WAIT=300
  CUR_WAIT=0
  echo -e "\033[0;33mWaiting up to $MAX_WAIT seconds for Confluent Control Center to start\033[0m"
  docker container logs control-center > /tmp/out.txt 2>&1
  while [[ ! $(cat /tmp/out.txt) =~ "Started NetworkTrafficServerConnector" ]]; do
    sleep 10
    docker container logs control-center > /tmp/out.txt 2>&1
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: The logs in control-center container do not show 'Started NetworkTrafficServerConnector' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
      exit 1
    fi
  done
  echo -e "\033[0;33mControl Center has started!\033[0m"
fi

# Verify Docker containers started
if [[ $(docker container ps) =~ "Exit 137" ]]; then
  echo -e "\nERROR: At least one Docker container did not start properly, see 'docker container ps'. Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)?\n"
  exit 1
fi
