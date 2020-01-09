#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "git"
verify_installed "ansible"
verify_installed "ansible-playbook"

if [ ! -d ${DIR}/cp-ansible ]
then
    log "INFO: Getting cp-ansible from Github."
    git clone https://github.com/confluentinc/cp-ansible
fi

# copy custom files
cp ${DIR}/hosts.yml ${DIR}/cp-ansible/

docker-compose down -v
docker-compose up -d

log "INFO: Checking Ansible can connect over DOCKER."
cd ${DIR}/cp-ansible
ansible -i hosts.yml all -m ping
cd ${DIR}

# ls /etc/systemd/system/
log "INFO: Restarting everything."
docker exec zookeeper1 systemctl restart confluent-zookeeper
docker exec broker1 systemctl restart confluent-kafka
docker exec broker2 systemctl restart confluent-kafka
docker exec broker3 systemctl restart confluent-kafka
docker exec schema-registry systemctl restart confluent-schema-registry
docker exec connect systemctl restart confluent-kafka-connect
docker exec ksql-server systemctl restart confluent-ksql
docker exec rest-proxy systemctl restart confluent-kafka-rest
docker exec control-center systemctl restart confluent-control-center

../../scripts/wait-for-connect-and-controlcenter.sh -b

log "INFO: Now you can modify the playbooks and run ansible-playbook -i hosts.yml all.yml"
#ansible-playbook -i hosts.yml all.yml

# if it fails, try to re-run this command
# ansible-playbook -vvvv -i hosts.yml all.yml
