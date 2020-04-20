#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

HOSTS_FILE=${1:-hosts-plaintext.yml}
if [ ! -f ${HOSTS_FILE} ]
then
     logerror "ERROR: ${HOSTS_FILE} is not set"
     exit 1
fi

verify_installed "git"
verify_installed "ansible"
verify_installed "ansible-playbook"

log "Installing using 5.3.1 TAG"
export TAG=5.3.1

# Offer to refresh images
ret=$(docker images --format "{{.Repository}}|{{.Tag}}|{{.CreatedSince}}" | grep vdesabou/cp-ansible-playground-zookeeper1 | grep "$TAG" | cut -d "|" -f 3)
if [ "$ret" != "" ]
then
  log "Your vdesabou/cp-ansible-playground Docker images were pulled $ret"
  read -p "Do you want to download new ones? (y/n)?" choice
  case "$choice" in
  y|Y )
    docker pull vdesabou/cp-ansible-playground-zookeeper1:$TAG
    docker pull vdesabou/cp-ansible-playground-broker1:$TAG
    docker pull vdesabou/cp-ansible-playground-broker2:$TAG
    docker pull vdesabou/cp-ansible-playground-broker3:$TAG
    docker pull vdesabou/cp-ansible-playground-schema-registry:$TAG
    docker pull vdesabou/cp-ansible-playground-connect:$TAG
    docker pull vdesabou/cp-ansible-playground-rest-proxy:$TAG
    docker pull vdesabou/cp-ansible-playground-ksql-server:$TAG
    docker pull vdesabou/cp-ansible-playground-control-center:$TAG
  ;;
  n|N ) ;;
  * ) logerror "ERROR: invalid response!";exit 1;;
  esac
fi

GIT_BRANCH="5.3.1-post"

rm -rf ${DIR}/cp-ansible
log "Getting cp-ansible from Github (branch $GIT_BRANCH)"
cd ${DIR}
git clone https://github.com/confluentinc/cp-ansible
cd ${DIR}/cp-ansible
git checkout "${GIT_BRANCH}"

# copy custom files
cp ${DIR}/${HOSTS_FILE} ${DIR}/cp-ansible/

docker-compose down -v
docker-compose up -d

log "INFO: Checking Ansible can connect over DOCKER."
cd ${DIR}/cp-ansible
ansible -i ${HOSTS_FILE} all -m ping

log "INFO: Now upgrading to 5.4.1"

GIT_BRANCH="5.4.1-post"
git fetch
git checkout "${GIT_BRANCH}"

log "Upgrading zookeeper"
ansible-playbook -i ${HOSTS_FILE} upgrade_zookeeper.yml

log "Upgrading brokers"
ansible-playbook -i ${HOSTS_FILE} upgrade_kafka_broker.yml -e kafka_broker_upgrade_start_version=5.3.1

log "Upgrading schema-registry"
ansible-playbook -i ${HOSTS_FILE} upgrade_schema_registry.yml

log "Upgrading connect"
ansible-playbook -i ${HOSTS_FILE} upgrade_kafka_connect.yml

log "Upgrading ksql-server"
ansible-playbook -i ${HOSTS_FILE} upgrade_ksql.yml

log "Upgrading rest-proxy"
ansible-playbook -i ${HOSTS_FILE} upgrade_kafka_rest.yml

log "Upgrading control-center"
ansible-playbook -i ${HOSTS_FILE} upgrade_control_center.yml

cd ${DIR}