#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "git"
verify_installed "ansible"
verify_installed "ansible-playbook"


CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

${DIR}/../ccloud-demo/ccloud-generate-env-vars.sh ${CONFIG_FILE}

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

# Offer to refresh images
ret=$(docker images --format "{{.Repository}}|{{.Tag}}|{{.CreatedSince}}" | grep vdesabou/cp-ansible-playground-connect | grep "$TAG" | cut -d "|" -f 3)
if [ "$ret" != "" ]
then
  log "Your vdesabou/cp-ansible-playground Docker images were pulled $ret"
  read -p "Do you want to download new ones? (y/n)?" choice
  case "$choice" in
  y|Y )
    docker pull vdesabou/cp-ansible-playground-connect:$TAG
    docker pull vdesabou/cp-ansible-playground-ksql-server:$TAG
    docker pull vdesabou/cp-ansible-playground-control-center:$TAG
  ;;
  n|N ) ;;
  * ) logerror "ERROR: invalid response!";exit 1;;
  esac
fi

if ! version_gt $TAG_BASE "5.9.0"; then
        logerror "ERROR: This can only be run with version greater than 6.0.0"
        exit 0
fi

if [ "$TAG" = "6.0.0" ]
then
  GIT_BRANCH="6.0.0-post"
else
    logerror "ERROR: Version $TAG not supported. Only 6.0.0 are supported"
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

HOSTS_FILE="hosts-ccloud.yml"
#HOSTS_FILE="hosts-ccloud-5.4.1.yml"
BOOTSTRAP_SERVER=$(echo "$BOOTSTRAP_SERVERS" | cut -d ":" -f 1)
SCHEMA_REGISTRY_SERVER=$(echo $SCHEMA_REGISTRY_URL | cut -d "/" -f3)
sed -e "s|_BOOTSTRAP_SERVER_|$BOOTSTRAP_SERVER:9092|g" \
    -e "s|_SCHEMA_REGISTRY_SERVER_|$SCHEMA_REGISTRY_SERVER|g" \
    -e "s|_SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    -e "s|_CLOUD_KEY_|$CLOUD_KEY|g" \
    -e "s|_CLOUD_SECRET_|$CLOUD_SECRET|g" \
    -e "s|_CONFLUENT_LICENSE_|$CONTROL_CENTER_LICENSE|g" \
    ${DIR}/hosts-ccloud-template.yml > ${DIR}/${HOSTS_FILE}


# copy custom files
cp ${DIR}/${HOSTS_FILE} ${DIR}/cp-ansible/

docker-compose down -v
docker-compose up -d

cd ${DIR}/cp-ansible

log "INFO: Now you can modify the playbooks and run ansible-playbook -i ${HOSTS_FILE} all.yml"
ansible-playbook -i ${HOSTS_FILE} all.yml
cd ${DIR}