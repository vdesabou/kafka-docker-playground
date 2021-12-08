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

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: This example is working starting from CP 5.4 only"
    exit 111
fi

GIT_BRANCH="$TAG-post"
ANSIBLE_VER=$(get_ansible_version)

# https://docs.confluent.io/ansible/current/ansible-download.html#download-ansible-for-ansible-2-11-or-higher-hosts
if version_gt $ANSIBLE_VER "2.10" && version_gt $TAG "6.9.9"
then
    log "Using ansible-galaxy to install cp-ansible"
    ansible-galaxy collection install git+https://github.com/confluentinc/cp-ansible.git
else
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
  cd ${DIR}/cp-ansible
fi

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$2
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  log "Using $DOCKER_COMPOSE_FILE_OVERRIDE"
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker-compose -f ${DIR}/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker-compose -f ${DIR}/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} up -d

log "Checking Ansible can connect over DOCKER."
ansible -i ${HOSTS_FILE} all -m ping

# https://docs.confluent.io/ansible/current/ansible-install.html
if version_gt $ANSIBLE_VER "2.10" && version_gt $TAG "6.9.9"
then
  export ANSIBLE_CONFIG=${DIR}/ansible.cfg
  log "Now you can modify the playbooks and run ansible-playbook -i ${HOSTS_FILE} confluent.platform.all"
  retry ansible-playbook -i ${HOSTS_FILE} confluent.platform.all
else
  log "Now you can modify the playbooks and run ansible-playbook -i ${HOSTS_FILE} all.yml"
  ansible-playbook -i ${HOSTS_FILE} all.yml
  cd ${DIR}
fi