#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

component="$1"
domain="$2"

if [ "$component" = "" ]
then
  logerror "ERROR: component name is not provided as argument!"
  exit 1
fi

case "${component}" in
  zookeeper|broker|schema-registry|connect)
  ;;
  *)
    logerror "ERROR: component name not valid ! Should be one of zookeeper, broker, schema-registry or connect"
    exit 1
  ;;
esac

get_jmx_metrics "$component" "$domain"