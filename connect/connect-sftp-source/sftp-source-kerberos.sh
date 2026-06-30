#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "3.1.99"
then
     logwarn "minimal supported connector version is 3.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.kerberos.yml"

# following https://www.confluent.io/blog/containerized-testing-with-kerberos-and-ssh/
log "Add kerberos principals"
playground container exec --container kdc-server --command "kadmin.local" << EOF
addprinc -randkey host/ssh-server.kerberos-demo.local@EXAMPLE.COM
ktadd -k /sshserver.keytab host/ssh-server.kerberos-demo.local@EXAMPLE.COM
addprinc -randkey sshuser@EXAMPLE.COM
ktadd -k /sshuser.keytab sshuser@EXAMPLE.COM
listprincs
EOF

log "Copy sshuser.keytab to connect container /tmp/sshuser.keytab"
playground container cp --source kdc-server:/sshuser.keytab --destination .
playground container cp --source sshuser.keytab --destination connect:/tmp/sshuser.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     playground container exec --container connect --root --command "chown appuser:appuser /tmp/sshuser.keytab"
fi

log "Copy sshserver.keytab to ssh server /etc/krb5.keytab"
playground container cp --source kdc-server:/sshserver.keytab --destination .
playground container cp --source sshserver.keytab --destination ssh-server:/etc/krb5.keytab
playground container exec --container ssh-server --root --command "chown root:root /etc/krb5.keytab"

log "Add sshuser"
playground container exec --container ssh-server --command "adduser sshuser --gecos \"First Last,RoomNumber,WorkPhone,HomePhone\"" << EOF
confluent
confluent
EOF

playground container exec --container ssh-server --command "bash" << EOF
mkdir -p /home/sshuser/upload/input
mkdir -p /home/sshuser/upload/error
mkdir -p /home/sshuser/upload/finished

chown -R sshuser /home/sshuser/upload
EOF

# FIXTHIS: it is required to do kinit manually
playground container exec --container connect --command "kinit sshuser -k -t /tmp/sshuser.keytab"
# if required to troubleshoot
# playground container exec -i --privileged --user root connect bash -c "yum update -y && yum install openssh-clients -y"

echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source.csv
playground container cp --source csv-sftp-source.csv --destination ssh-server:/home/sshuser/upload/input/
rm -f csv-sftp-source.csv

log "Creating CSV SFTP Source connector"
playground connector create-or-update --connector sftp-source-kerberos-csv  << EOF
{
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
     "cleanup.policy":"NONE",
     "behavior.on.error":"IGNORE",
     "input.path": "/home/sshuser/upload/input",
     "error.path": "/home/sshuser/upload/error",
     "finished.path": "/home/sshuser/upload/finished",
     "input.file.pattern": ".*\\\\.csv",
     "sftp.username":"sshuser",
     "kerberos.keytab.path": "/tmp/sshuser.keytab",
     "kerberos.user.principal": "sshuser",
     "sftp.host":"ssh-server",
     "sftp.port":"22",
     "kafka.topic": "sftp-testing-topic",
     "csv.first.row.as.header": "true",
     "schema.generation.enabled": "true"
}
EOF

sleep 15

log "Verifying topic sftp-testing-topic"
playground topic consume --topic sftp-testing-topic --min-expected-messages 2 --timeout 60