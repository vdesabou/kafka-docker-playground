#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "git"
verify_installed "ansible"
verify_installed "ansible-playbook"

if [ ! -d ${DIR}/cp-ansible ]
then
    echo -e "\033[0;33mINFO: Getting cp-ansible from Github.\033[0m"
    git clone https://github.com/confluentinc/cp-ansible
fi

# copy custom files
cp ${DIR}/hosts.yml ${DIR}/cp-ansible/

docker-compose down -v
docker-compose up -d

echo -e "\033[0;33mINFO: Checking Ansible can connect over DOCKER.\033[0m"
cd ${DIR}/cp-ansible
ansible -i hosts.yml all -m ping
cd ${DIR}

# ls /etc/systemd/system/
echo -e "\033[0;33mINFO: Restarting everything.\033[0m"
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

echo -e "\033[0;33mINFO: Now you can modify the playbooks and run ansible-playbook -i hosts.yml all.yml\033[0m"
#ansible-playbook -i hosts.yml all.yml

# if it fails, try to re-run this command
# ansible-playbook -vvvv -i hosts.yml all.yml
