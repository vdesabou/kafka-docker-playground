environment=`get_environment_used`
connector="${args[--connector]}"

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

type=$(curl -s http://localhost:8083/connectors\?expand\=status\&expand\=info | jq -r '. | to_entries[] | [ .value.info.type]|join(":|:")')
if [ "$type" != "sink" ]
then
  logerror "Connector $connector is a $type connector, it must be a sink to show the lag !"
  exit 1 
fi

log "Show lag for sink connector $connector"
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe