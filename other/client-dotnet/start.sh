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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml" -a -b

log "Starting producer"
docker exec -i client-dotnet bash -c "dotnet DotNet.dll produce test1"

log "Starting consumer"
docker exec -i client-dotnet bash -c "dotnet DotNet.dll consume test1"