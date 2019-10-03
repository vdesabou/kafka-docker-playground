#!/bin/bash

IGNORE_CONNECT_STARTUP=${1:-FALSE}
IGNORE_CONTROL_CENTER_STARTUP=${2:-FALSE}

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
verify_installed "keytool"

OLDDIR=$PWD

cd ${OLDDIR}/../sasl-ssl/security

echo "Generate keys and certificates used for SSL"
./certs-create.sh

cd ${OLDDIR}/../sasl-ssl
docker-compose down -v 
docker-compose up -d

if [ "${IGNORE_CONNECT_STARTUP}" == "FALSE" ]
then
  # Verify Kafka Connect has started within MAX_WAIT seconds
  MAX_WAIT=120
  CUR_WAIT=0
  echo "Waiting up to $MAX_WAIT seconds for Kafka Connect to start"
  while [[ ! $(docker-compose logs connect) =~ "Finished starting connectors and tasks" ]]; do
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: The logs in connect container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot with 'docker-compose ps' and 'docker-compose logs'.\n"
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
  while [[ ! $(docker-compose logs control-center) =~ "Started NetworkTrafficServerConnector" ]]; do
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: The logs in control-center container do not show 'Started NetworkTrafficServerConnector' after $MAX_WAIT seconds. Please troubleshoot with 'docker-compose ps' and 'docker-compose logs'.\n"
      exit 1
    fi
  done
  echo "Control Center has started!"
fi

# Verify Docker containers started
if [[ $(docker-compose ps) =~ "Exit 137" ]]; then
  echo -e "\nERROR: At least one Docker container did not start properly, see 'docker-compose ps'. Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)?\n"
  exit 1
fi

cd ${OLDDIR}