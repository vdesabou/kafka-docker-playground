#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# loading env variables
source ${DIR}/../../scripts/utils.sh

docker-compose up -d