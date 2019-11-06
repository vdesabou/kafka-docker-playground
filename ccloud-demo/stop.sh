#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
${DIR}/../ccloud-demo/Utils.sh

CCLOUD_PROMPT_FMT='You will be using Confluent Cloud config: user={{color "green" "%u"}}, environment={{color "red" "%E"}}, cluster={{color "cyan" "%K"}}, api key={{color "yellow" "%a"}})'
ccloud prompt -f "$CCLOUD_PROMPT_FMT"

read -p "Continue (y/n)?" choice
case "$choice" in
  y|Y ) ;;
  n|N ) exit 0;;
  * ) echo "ERROR: invalid response!";exit 1;;
esac

# Delete topic in Confluent Cloud
echo "Delete topic customer-avro"
ccloud kafka topic delete customer-avro

echo "Delete topic mysql-application"
ccloud kafka topic delete mysql-application

echo "Delete connector mysql-source"
curl -X DELETE localhost:8083/connectors/mysql-source
echo "Delete connector HttpSinkBasicAuth"
curl -X DELETE localhost:8083/connectors/HttpSinkBasicAuth

docker-compose down -v