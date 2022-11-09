#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99"; then
    logwarn "WARN: Skipped before 6.x"
    exit 111
fi

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

if ! version_gt $TAG_BASE "5.4.99"; then
    logwarn "WARN: This example is working starting from CP 5.5 only"
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

cp ${DIR}/log4j/* /tmp/

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
if [[ "${HOSTS_FILE}" == "hosts-rbac"* ]]
then
  DOCKER_COMPOSE_FILE_OVERRIDE=${DIR}/docker-compose.ldap.yml
  if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
  then
    log "Using $DOCKER_COMPOSE_FILE_OVERRIDE"
    ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  fi

  mkdir -p ${DIR}/ldap/ldap_certs
  cd ${DIR}/ldap/ldap_certs
  log "LDAPS: Creating a Root Certificate Authority (CA)"
  openssl req -new -x509 -days 365 -nodes -out ca.crt -keyout ca.key -subj "/CN=root-ca"
  log "LDAPS: Generate the LDAPS server key and certificate"
  openssl req -new -nodes -out server.csr -keyout server.key -subj "/CN=openldap"
  openssl x509 -req -in server.csr -days 365 -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt
  log "LDAPS: Create a JKS truststore"
  rm -f ldap_truststore.jks
  # We import the test CA certificate
  keytool -import -v -alias testroot -file ca.crt -keystore ldap_truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
  log "LDAPS: Displaying truststore"
  keytool -list -keystore ldap_truststore.jks -storepass 'welcome123' -v
  cd -
fi

if [ "${HOSTS_FILE}" == "hosts-rbac-provided-certificates-repro-ANSIENG-983.yml" ]
then
  log "Replacing certs-create.sh to reproduce ANSIENG-983"
  cp ${DIR}/repro-ANSIENG-983/certs-create.sh ${DIR}/security/
fi

if [ "${HOSTS_FILE}" == "hosts-rbac-provided-certificates.yml" ] || [ "${HOSTS_FILE}" == "hosts-rbac-provided-certificates-repro-ANSIENG-983.yml" ]
then
  DOCKER_COMPOSE_FILE_OVERRIDE=${DIR}/docker-compose.rbac-provided-certificates.yml
  if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
  then
    log "Using $DOCKER_COMPOSE_FILE_OVERRIDE"
    ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  fi

  cd ${DIR}/security
  log "🔐 Generate keys and certificates used for SSL"
  docker run -u0 --rm -v $PWD:/tmp vdesabou/cp-ansible-playground-connect:${TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
  cd -
  rm -rf /tmp/security
  cp -R ${DIR}/security /tmp/
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