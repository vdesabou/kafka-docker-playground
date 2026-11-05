#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

maybe_delete_ccloud_environment

docker rm -f client-rust-ccloud-producer client-rust-ccloud-consumer > /dev/null 2>&1
