#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.kerberos.yml"

# following https://www.confluent.io/blog/containerized-testing-with-kerberos-and-ssh/
log "Add kerberos principals"
docker exec -i kdc-server kadmin.local << EOF
addprinc -randkey host/ssh-server.kerberos-demo.local@EXAMPLE.COM
ktadd -k /sshserver.keytab host/ssh-server.kerberos-demo.local@EXAMPLE.COM
addprinc -randkey sshuser@EXAMPLE.COM
ktadd -k /sshuser.keytab sshuser@EXAMPLE.COM
listprincs
EOF

log "Copy sshuser.keytab to connect container /tmp/sshuser.keytab"
docker cp kdc-server:/sshuser.keytab .
docker cp sshuser.keytab connect:/tmp/sshuser.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/sshuser.keytab
fi

log "Copy sshserver.keytab to ssh server /etc/krb5.keytab"
docker cp kdc-server:/sshserver.keytab .
docker cp sshserver.keytab ssh-server:/etc/krb5.keytab
docker exec -u 0 ssh-server chown root:root /etc/krb5.keytab

log "Add sshuser"
docker exec -i ssh-server adduser sshuser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" << EOF
confluent
confluent
EOF

docker exec ssh-server bash -c "
mkdir -p /home/sshuser/upload/input
mkdir -p /home/sshuser/upload/error
mkdir -p /home/sshuser/upload/finished

chown -R sshuser /home/sshuser/upload
"

# FIXTHIS: it is required to do kinit manually
docker exec connect kinit sshuser -k -t /tmp/sshuser.keytab
# if required to troubleshoot
# docker exec -i --privileged --user root connect bash -c "yum update -y && yum install openssh-clients -y"

echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source.csv
docker cp csv-sftp-source.csv ssh-server:/home/sshuser/upload/input/
rm -f csv-sftp-source.csv

log "Creating CSV SFTP Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
               "cleanup.policy":"NONE",
               "behavior.on.error":"IGNORE",
               "input.path": "/home/sshuser/upload/input",
               "error.path": "/home/sshuser/upload/error",
               "finished.path": "/home/sshuser/upload/finished",
               "input.file.pattern": ".*\\.csv",
               "sftp.username":"sshuser",
               "kerberos.keytab.path": "/tmp/sshuser.keytab",
               "kerberos.user.principal": "sshuser",
               "sftp.host":"ssh-server",
               "sftp.port":"22",
               "kafka.topic": "sftp-testing-topic",
               "csv.first.row.as.header": "true",
               "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/sftp-source-kerberos-csv/config | jq .

sleep 5

log "Verifying topic sftp-testing-topic"
playground topic consume --topic sftp-testing-topic --min-expected-messages 2