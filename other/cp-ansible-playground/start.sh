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

if [ "$TAG" = "5.3.1" ]
then
  GIT_BRANCH="5.3.1-post"
elif [ "$TAG" = "5.4.0" ]
then
  GIT_BRANCH="5.4.0-post"
elif [ "$TAG" = "5.4.1" ]
then
  GIT_BRANCH="5.4.1-post"
elif [ "$TAG" = "5.5.0" ]
then
  GIT_BRANCH="5.5.0-post"
elif [ "$TAG" = "5.5.1" ]
then
  GIT_BRANCH="5.5.1-post"
elif [ "$TAG" = "5.5.2" ]
then
  GIT_BRANCH="5.5.2-post"
elif [ "$TAG" = "5.5.3" ]
then
  GIT_BRANCH="5.5.3-post"
elif [ "$TAG" = "5.5.4" ]
then
  GIT_BRANCH="5.5.4-post"
elif [ "$TAG" = "6.0.0" ]
then
  GIT_BRANCH="6.0.0-post"
elif [ "$TAG" = "6.0.1" ]
then
  GIT_BRANCH="6.0.1-post"
elif [ "$TAG" = "6.0.2" ]
then
  GIT_BRANCH="6.0.2-post"
elif [ "$TAG" = "6.1.0" ]
then
  GIT_BRANCH="6.1.0-post"
elif [ "$TAG" = "6.1.1" ]
then
  GIT_BRANCH="6.1.1-post"
else
    logerror "ERROR: Version $TAG not supported. Only 5.3.1, 5.4.0, 5.4.1, 5.5.0, 5.5.1, 5.5.2, 5.5.3, 5.5.4, 6.0.0, 6.0.1, 6.0.2, 6.1.0 and 6.1.1 are supported"
    exit 1
fi

if [ -d ${DIR}/cp-ansible ]
then
  log "cp-ansible repository already exists"
  read -p "Do you want to get the latest version? (y/n)?" choice
  case "$choice" in
  y|Y )
    rm -rf ${DIR}/cp-ansible
    log "Getting cp-ansible from Github (branch $GIT_BRANCH)"
    cd ${DIR}
    git clone https://github.com/confluentinc/cp-ansible
    cd ${DIR}/cp-ansible
    git checkout "${GIT_BRANCH}"
  ;;
  n|N ) ;;
  * ) logerror "ERROR: invalid response!";exit 1;;
  esac
else
    log "Getting cp-ansible from Github (branch $GIT_BRANCH)"
    cd ${DIR}
    git clone https://github.com/confluentinc/cp-ansible
    cd ${DIR}/cp-ansible
    git checkout "${GIT_BRANCH}"
fi

# copy custom files
cp ${DIR}/${HOSTS_FILE} ${DIR}/cp-ansible/

docker-compose down -v --remove-orphans
docker-compose up -d

log "INFO: Checking Ansible can connect over DOCKER."
cd ${DIR}/cp-ansible
ansible -i ${HOSTS_FILE} all -m ping

log "INFO: Now you can modify the playbooks and run ansible-playbook -i ${HOSTS_FILE} all.yml"
ansible-playbook -i ${HOSTS_FILE} all.yml
cd ${DIR}