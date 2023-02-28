environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi
connect_url="http://localhost:8083"
security_certs=""
if [ "$environment" != "plaintext" ]
then
    connect_url="https://localhost:8083"
    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

    security_certs="--cert $DIR_CLI/../../environment/$environment/security/connect.certificate.pem --key $DIR_CLI/../../environment/$environment/security/connect.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
fi

package="${args[--package]}"
level="${args[--level]}"

log "Set log level for package $package to $level"
curl $security_certs -s --request PUT \
  --url "$connect_url/admin/loggers/$package" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data "{
 \"level\": \"$level\"
}" | jq .

playground connect-log-level get -p "$package"