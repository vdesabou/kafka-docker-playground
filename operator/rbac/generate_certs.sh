#!/bin/bash

DIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
COMPONENTS=(connectors controlcenter kafka ksql replicator schemaregistry zookeeper)
NAMESPACE=${1:-operator}
DOMAIN=${2:-"platformops.aws.devel.cpdev.cloud"}
OUT_FOLDER="${DIR}/certs/component-certs"

mkdir -p ${OUT_FOLDER}

[[ $# -gt 2 ]] && { echo "Usage: $0 <namespace> <domain>"; exit 1; }

echo "Generating component certs for $DOMAIN into ${OUT_FOLDER}"

for component in ${COMPONENTS[@]}; do
    dir="${OUT_FOLDER}/${component}"
    config_file_name="${component}-server.json"
    if [[ $component = "schemaregistry" ]]; then
      cn="sr"
    elif [[ $component = "controlcenter" ]]; then
      cn="c3"
    elif [[ $component = "connectors" ]]; then
      cn="connect"
    else
      cn=$component
    fi

    mkdir -p ${dir}
    echo "{\
        \"CN\": \"${cn}\",
        \"hosts\": [\
            \"*.${DOMAIN}\",
            \"*.cluster.local\",
            \"*.svc.cluster.local\",
            \"*.${NAMESPACE}.svc.cluster.local\",
            \"*.kafka.${NAMESPACE}.svc.cluster.local\",
            \"*.${component}.${NAMESPACE}.svc.cluster.local\",
            \"${cn}\"
        ],
        \"key\": {
            \"algo\": \"rsa\",
            \"size\": 2048
        },
        \"names\": [
            {
            \"C\": \"US\",
            \"ST\": \"CA\",
            \"L\": \"Palo Alto\"
            }
        ]
        }" > "${dir}/${config_file_name}"
    cfssl gencert -ca="${DIR}/certs/ca.pem" -ca-key="${DIR}/certs/ca-key.pem" -config="${DIR}/certs/ca-config.json" -profile=server "${dir}/${config_file_name}" | cfssljson -bare "${dir}/${component}"
done
