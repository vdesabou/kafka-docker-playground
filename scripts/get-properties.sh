#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

container="$1"

if [ "$container" = "" ]
then
  logerror "ERROR: container name is not provided as argument!"
  exit 1
fi

docker exec -i $container sh << EOF
ps -ef | grep properties | grep java | grep -v grep | awk '{ print \$NF }' > /tmp/propertie_file
propertie_file=\$(cat /tmp/propertie_file)
if [ ! -f \$propertie_file ]
then
  echo 'ERROR: Could not determine properties file!'
  exit 1
fi
cat \$propertie_file | grep -v None | grep . | sort
EOF

