#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "3.1.99"
then
     logwarn "minimal supported connector version is 3.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

log "generate ssh host key"
rm -rf ssh_host*
ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key -P "mypassword"

# needs to be a RSA key
ssh-keygen -p -f ssh_host_rsa_key -m pem -P mypassword -N mypassword -b 2048

RSA_PUBLIC_KEY=$(cat ssh_host_rsa_key.pub)
RSA_PRIVATE_KEY=$(awk '{printf "%s\\r\\n", $0}' ssh_host_rsa_key)

log "RSA_PUBLIC_KEY=$RSA_PUBLIC_KEY"
log "RSA_PRIVATE_KEY=$RSA_PRIVATE_KEY"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ssh-key.yml"

docker exec sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input
mkdir -p /chroot/home/foo/upload/error
mkdir -p /chroot/home/foo/upload/finished

chown -R foo /chroot/home/foo/upload
"

echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source.csv
docker cp csv-sftp-source.csv sftp-server:/chroot/home/foo/upload/input/
rm -f csv-sftp-source.csv

log "Creating CSV SFTP Source connector"
playground connector create-or-update --connector sftp-source-ssh-key  << EOF
{
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
     "cleanup.policy":"NONE",
     "behavior.on.error":"IGNORE",
     "input.path": "/home/foo/upload/input",
     "error.path": "/home/foo/upload/error",
     "finished.path": "/home/foo/upload/finished",
     "input.file.pattern": ".*\\\\.csv",
     "sftp.username":"foo",
     "sftp.password": "",
     "tls.private.key": "$RSA_PRIVATE_KEY",
     "tls.public.key": "$RSA_PUBLIC_KEY",
     "tls.passphrase": "mypassword",
     "sftp.host":"sftp-server",
     "sftp.port":"22",
     "kafka.topic": "sftp-testing-topic",
     "csv.first.row.as.header": "true",
     "schema.generation.enabled": "true"
}
EOF

sleep 15

log "Verifying topic sftp-testing-topic"
playground topic consume --topic sftp-testing-topic --min-expected-messages 2 --timeout 60