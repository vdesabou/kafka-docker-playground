environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi
connect_url="$connect_url"
security_certs=""
if [ "$environment" != "plaintext" ]
then
    connect_url="https://localhost:8083"
    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

    security_certs="--cert $DIR_CLI/../../environment/$environment/security/connect.certificate.pem --key $DIR_CLI/../../environment/$environment/security/connect.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
fi

logger="${args[logger]}"

if [[ -n "$logger" ]]
then
  log "Get log level for logger $logger"
  curl $security_certs -s "$connect_url/admin/loggers/$logger" | jq .
else
    log "Get log level for all loggers"
  curl $security_certs -s "$connect_url/admin/loggers" | jq .
fi