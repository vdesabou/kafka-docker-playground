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

function get_examples_list_with_fzf() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' | fzf --delimiter / --with-nth '-3,-2,-1' --preview 'cat {}'
  else
    find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' | fzf --delimiter / --with-nth '-3,-2,-1' --preview 'bat --style=numbers --color=always --line-range :500 {}'
  fi
}

function get_examples_list_with_fzf_without_repro() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --delimiter / --with-nth '-3,-2,-1' --preview 'cat {}'
  else
    find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --delimiter / --with-nth '-3,-2,-1' --preview 'bat --style=numbers --color=always --line-range :500 {}'
  fi
}

function get_examples_list_with_fzf_without_repro_sink_only() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    find $dir2 -name \*.sh ! -name 'stop.sh' -path '*/connect-*-sink/*' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --delimiter / --with-nth '-3,-2,-1' --preview 'cat {}'
  else
    find $dir2 -name \*.sh ! -name 'stop.sh' -path '*/connect-*-sink/*' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --delimiter / --with-nth '-3,-2,-1' --preview 'bat --style=numbers --color=always --line-range :500 {}'
  fi
}