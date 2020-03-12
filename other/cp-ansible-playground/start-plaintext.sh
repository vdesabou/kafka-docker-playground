#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "git"
verify_installed "ansible"
verify_installed "ansible-playbook"

HOSTS_FILE="hosts-plaintext.yml"

if [ "$TAG" = "5.3.1" ]
then
  GIT_BRANCH="5.3.1-post"
elif [ "$TAG" = "5.4.0" ]
then
  GIT_BRANCH="5.4.0-post"
elif [ "$TAG" = "5.4.1" ]
then
  GIT_BRANCH="5.4.1-post"
else
    logerror "ERROR: Version $TAG not supported. Only 5.3.1, 5.4.0 or 5.4.1 are supported"
    exit 1
fi

if [ -d ${DIR}/cp-ansible ]
then
  logwarn "${DIR}/cp-ansible already exists ! It will be deleted !"
  check_if_continue
fi

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

log "INFO: Now you can modify the playbooks and run ansible-playbook -i ${HOSTS_FILE} all.yml"
ansible-playbook -i ${HOSTS_FILE} all.yml
cd ${DIR}