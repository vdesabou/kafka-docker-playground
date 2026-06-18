#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
if version_gt $TAG_BASE "8.2.99"
then
    docker run --quiet --rm ${CP_REST_PROXY_IMAGE}:${CP_REST_PROXY_TAG} type microdnf > /dev/null 2>&1
    if [ $? != 0 ]
    then
      log "🛠️ Restoring ubi minimal into ${CP_REST_PROXY_IMAGE}:${CP_REST_PROXY_TAG}"
      pm_tmp_dir=$(mktemp -d -t pg-pm-XXXXXXXXXX)
      cat << EOF > $pm_tmp_dir/Dockerfile
FROM redhat/ubi9-minimal:latest AS pm
RUN rm -f /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/subuid /etc/subgid

FROM ${CP_REST_PROXY_IMAGE}:${CP_REST_PROXY_TAG}
USER root
COPY --from=pm / /
RUN ldconfig
USER appuser
EOF
      DOCKER_BUILDKIT=0 docker build -t ${CP_REST_PROXY_IMAGE}:${CP_REST_PROXY_TAG} $pm_tmp_dir
      rm -rf $pm_tmp_dir
    fi
fi
set -e

playground start-environment --environment sasl-ssl --docker-compose-override-file "${PWD}/docker-compose.sasl-ssl.yml"

# run as root for linux case where key is owned by root user
log "HTTP client using clientrestproxy principal"
docker exec --privileged --user root restproxy curl -X POST --cert /etc/kafka/secrets/clientrestproxy.certificate.pem --key /etc/kafka/secrets/clientrestproxy.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt -H "Content-Type: application/vnd.kafka.json.v2+json" -H "Accept: application/vnd.kafka.v2+json" --data '{"records":[{"value":{"foo":"bar"}}]}' "https://localhost:8086/topics/jsontest"
