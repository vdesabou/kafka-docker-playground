#!/bin/bash

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "jq"
verify_installed "docker-compose"

docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml down -v
docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml up -d

../../WaitForConnectAndControlCenter.sh connect-us $@
../../WaitForConnectAndControlCenter.sh connect-europe $@