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

if test -z "$(docker images -q cp-ansible-ubuntu:orig)"
then
     echo -e "\033[0;33mBuilding cp-ansible-ubuntu:orig docker image..it can take a while...\033[0m"
     docker build -t cp-ansible-ubuntu:orig .
fi

if [ ! -d ${DIR}/cp-ansible ]
then
    echo -e "\033[0;33mINFO: Getting cp-ansible from Github.\033[0m"
    git clone https://github.com/confluentinc/cp-ansible
    cd ${DIR}/cp-ansible
    # FIXTHIS: to remove once it is committed https://github.com/confluentinc/cp-ansible/pull/169
    # failed: [localhost] (item=confluent-kafka-connect-storage-common) => {"ansible_loop_var": "item", "cache_update_time": 1577980162, "cache_updated": false, "changed": false, "item": "confluent-kafka-connect-storage-common", "msg": "'/usr/bin/apt-get -y -o \"Dpkg::Options::=--force-confdef\" -o \"Dpkg::Options::=--force-confold\"      install 'confluent-kafka-connect-storage-common=5.3.1-1'' failed: E: Packages were downgraded and -y was used without --allow-downgrades.\n", "rc": 100, "stderr": "E: Packages were downgraded and -y was used without --allow-downgrades.\n", "stderr_lines": ["E: Packages were downgraded and -y was used without --allow-downgrades."], "stdout": "Reading package lists...\nBuilding dependency tree...\nReading state information...\nThe following packages will be DOWNGRADED:\n  confluent-kafka-connect-storage-common\n0 upgraded, 0 newly installed, 1 downgraded, 0 to remove and 10 not upgraded.\n", "stdout_lines": ["Reading package lists...", "Building dependency tree...", "Reading state information...", "The following packages will be DOWNGRADED:", "  confluent-kafka-connect-storage-common", "0 upgraded, 0 newly installed, 1 downgraded, 0 to remove and 10 not upgraded."]}

    #failed: [localhost] (item=confluent-control-center-fe) => {"ansible_loop_var": "item", "cache_update_time": 1577983194, "cache_updated": false, "changed": false, "item": "confluent-control-center-fe", "msg": "'/usr/bin/apt-get -y -o \"Dpkg::Options::=--force-confdef\" -o \"Dpkg::Options::=--force-confold\"      install 'confluent-control-center-fe=5.3.1-1'' failed: E: Packages were downgraded and -y was used without --allow-downgrades.\n", "rc": 100, "stderr": "E: Packages were downgraded and -y was used without --allow-downgrades.\n", "stderr_lines": ["E: Packages were downgraded and -y was used without --allow-downgrades."], "stdout": "Reading package lists...\nBuilding dependency tree...\nReading state information...\nThe following packages will be DOWNGRADED:\n  confluent-control-center-fe\n0 upgraded, 0 newly installed, 1 downgraded, 0 to remove and 12 not upgraded.\n", "stdout_lines": ["Reading package lists...", "Building dependency tree...", "Reading state information...", "The following packages will be DOWNGRADED:", "  confluent-control-center-fe", "0 upgraded, 0 newly installed, 1 downgraded, 0 to remove and 12 not upgraded."]}
    git checkout debian-changes
    cd ${DIR}
fi

# copy custom files
cp ${DIR}/hosts.yml ${DIR}/cp-ansible/

#docker-compose down -v
docker-compose up -d

cd ${DIR}/cp-ansible

echo -e "\033[0;33mINFO: Checking Ansible can connect over DOCKER.\033[0m"
ansible -i hosts.yml all -m ping

echo -e "\033[0;33mINFO: Run the all.yml playbook.\033[0m"
ansible-playbook -i hosts.yml all.yml

# if it fails, try to re-run this command
# ansible-playbook -vvvv -i hosts.yml all.yml


# ls /etc/systemd/system/
# systemctl start confluent-kafka
# systemctl start confluent-schema-registry

# create a new image from snapshot