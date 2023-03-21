#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export ORACLE_IMAGE="oracle/database:12.2.0.1-ee"
if [ ! -z "$CI" ]
then
     # if this is github actions, use private image.
     export ORACLE_IMAGE="vdesabou/oracle21"
fi

stop_all "$DIR"