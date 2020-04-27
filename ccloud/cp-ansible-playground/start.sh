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
    # docker pull vdesabou/cp-ansible-playground-rest-proxy:$TAG
    # docker pull vdesabou/cp-ansible-playground-ksql-server:$TAG
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
else
    logerror "ERROR: Version $TAG not supported. Only 5.3.1, 5.4.0, 5.4.1 or 5.5.0 are supported"
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
fi

HOSTS_FILE="hosts-ccloud.yml"
# generate kafka-admin.properties config

BOOTSTRAP_SERVER=$(echo "$BOOTSTRAP_SERVERS" | cut -d ":" -f 1)
SCHEMA_REGISTRY_SERVER=$(echo $SCHEMA_REGISTRY_URL | cut -d "/" -f3)
sed -e "s|_BOOTSTRAP_SERVER_|$BOOTSTRAP_SERVER|g" \
    -e "s|_SCHEMA_REGISTRY_SERVER_|$SCHEMA_REGISTRY_SERVER|g" \
    -e "s|_SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    -e "s|_CLOUD_KEY_|$CLOUD_KEY|g" \
    -e "s|_CLOUD_SECRET_|$CLOUD_SECRET|g" \
    -e "s|_CONFLUENT_LICENSE_|$CONTROL_CENTER_LICENSE|g" \
    ${DIR}/hosts-ccloud-template.yml > ${DIR}/${HOSTS_FILE}

# copy custom files
cp ${DIR}/${HOSTS_FILE} ${DIR}/cp-ansible/

# FIXTHIS: we need to do custom modifications in order to be able to override security.protocol to SASL_SSL
#
# We need to comment `*.security.protocol=` in cp-ansible/roles/confluent.kafka_connect/templates/connect-distributed.properties.j2, cp-ansible/roles/confluent.control_center/templates/control-center.properties.j2 and cp-ansible/roles/confluent.ksql/templates/ksql-server.properties.j2
sed -i.bak 's/^\(.*security.protocol=.*\)/#\1/g' ${DIR}/cp-ansible/roles/confluent.kafka_connect/templates/connect-distributed.properties.j2 ${DIR}/cp-ansible/roles/confluent.control_center/templates/control-center.properties.j2 ${DIR}/cp-ansible/roles/confluent.ksql/templates/ksql-server.properties.j2

docker-compose down -v
docker-compose up -d

cd ${DIR}/cp-ansible

log "INFO: Now you can modify the playbooks and run ansible-playbook -i ${HOSTS_FILE} all.yml"
ansible-playbook -i ${HOSTS_FILE} all.yml
cd ${DIR}