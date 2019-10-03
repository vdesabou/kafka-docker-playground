#!/bin/bash

IGNORE_CONNECT_STARTUP="FALSE"
IGNORE_CONTROL_CENTER_STARTUP="FALSE"

while getopts "h?ab" opt; do
    case "$opt" in
    h|\?)
        echo "possible options -a to ignore connect startup and -b to ignore control center"
        exit 0
        ;;
    a)  IGNORE_CONNECT_STARTUP="TRUE"
        ;;
    b)  IGNORE_CONTROL_CENTER_STARTUP="TRUE"
        ;;
    esac
done

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "jq"
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f ${DOCKER_COMPOSE_FILE_OVERRIDE} ]
then
  echo "Using ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  docker-compose -f ../nosecurity/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v 
  docker-compose -f ../nosecurity/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else 
  docker-compose down -v 
  docker-compose up -d
fi

if [ "${IGNORE_CONNECT_STARTUP}" == "FALSE" ]
then
  # Verify Kafka Connect has started within MAX_WAIT seconds
  MAX_WAIT=120
  CUR_WAIT=0
  echo "Waiting up to $MAX_WAIT seconds for Kafka Connect to start"
  while [[ ! $(docker container logs connect) =~ "Finished starting connectors and tasks" ]]; do
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: The logs in connect container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
      exit 1
    fi
  done
  echo "Connect has started!"
fi

if [ "${IGNORE_CONTROL_CENTER_STARTUP}" == "FALSE" ]
then
  # Verify Confluent Control Center has started within MAX_WAIT seconds
  MAX_WAIT=300
  CUR_WAIT=0
  echo "Waiting up to $MAX_WAIT seconds for Confluent Control Center to start"
  while [[ ! $(docker container logs control-center) =~ "Started NetworkTrafficServerConnector" ]]; do
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: The logs in control-center container do not show 'Started NetworkTrafficServerConnector' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
      exit 1
    fi
  done
  echo "Control Center has started!"
fi

# Verify Docker containers started
if [[ $(docker container ps) =~ "Exit 137" ]]; then
  echo -e "\nERROR: At least one Docker container did not start properly, see 'docker container ps'. Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)?\n"
  exit 1
fi