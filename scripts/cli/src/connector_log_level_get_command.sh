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

if [[ -n "$package" ]]
then
  log "Get log level for package $package"
  curl $security_certs -s "$connect_url/admin/loggers/$package" | jq .
else
  log "Get log level for all packages"
  curl $security_certs -s "$connect_url/admin/loggers" | jq .
fi