function get_environment_used() {
  if [ ! -f /tmp/playground-command ]
  then
    echo "error"
    return
  fi

  grep "environment/2way-ssl" /tmp/playground-command > /dev/null
  if [ $? = 0 ]
  then
    echo "2way-ssl"
    return
  fi

  grep "environment/sasl-ssl" /tmp/playground-command > /dev/null
  if [ $? = 0 ]
  then
    echo "sasl-ssl"
    return
  fi

  echo "plaintext"
}

function get_connector_list() {
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

  curl $security_certs -s "$connect_url/connectors" | jq -r '.[]'
}