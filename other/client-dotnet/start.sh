#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CORE_DOT_VERSION=${1:-3.1}

if [[ "$CORE_DOT_VERSION" = "3.1" ]]
then
     log "Using .NET Core version 3.1"
     export CORE_RUNTIME_TAG="3.1.2-bionic"
     export CORE_SDK_TAG="3.1.102-bionic"
     export CSPROJ_FILE="DotNet3.1.csproj"
else
     log "Using .NET Core version 2.2"
     export CORE_RUNTIME_TAG="2.2-stretch-slim"
     export CORE_SDK_TAG="2.2-stretch"
     export CSPROJ_FILE="DotNet2.2.csproj"
fi

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --wait-for-control-center

log "Starting producer"
docker exec -i client-dotnet bash -c "dotnet DotNet.dll produce test1"

log "Starting consumer. Logs are in /tmp/result.log"
docker exec -i client-dotnet bash -c "dotnet DotNet.dll consume test1" > /tmp/result.log 2>&1 &
sleep 5
cat /tmp/result.log
grep "alice" /tmp/result.log