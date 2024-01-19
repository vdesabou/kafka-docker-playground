function get_environment_used() {
  environment=$(playground state get run.environment)
}

function get_connect_url_and_security() {
  get_environment_used

  connect_url="http://localhost:8083"
  security=""
  if [[ "$environment" == "sasl-ssl" ]] || [[ "$environment" == "2way-ssl" ]]
  then
      connect_url="https://localhost:8083"
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="--cert $DIR_CLI/../../environment/$environment/security/connect.certificate.pem --key $DIR_CLI/../../environment/$environment/security/connect.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
  elif [[ "$environment" == "rbac-sasl-plain" ]]
  then
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="-u connectorSubmitter:connectorSubmitter"
  fi
}

function generate_fzf_find_files() {
  generate_get_examples_list_with_fzf_without_repro_sink_only
  generate_get_examples_list_with_fzf_without_repro
  generate_get_examples_list_with_fzf_ccloud_only
  generate_get_examples_list_with_fzf
}

function generate_get_examples_list_with_fzf_without_repro_sink_only () {
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/connect-*-sink/*' ! -path '*/scripts/*' ! -path '*/ora-*/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' > $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only
}

function generate_get_examples_list_with_fzf_without_repro () {
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/ora-*/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' > $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro
}

function generate_get_examples_list_with_fzf_ccloud_only () {
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/ccloud*' ! -path '*/ora-*/*' ! -path '*/security/*' > $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only
}

function generate_get_examples_list_with_fzf () {
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/ccloud/*' ! -path '*/ora-*/*' ! -path '*/security/*' > $root_folder/scripts/cli/get_examples_list_with_fzf
}

function get_ccloud_connect() {

  get_kafka_docker_playground_dir

  if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
  then
      logerror "ERROR: $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
      exit 1
  fi

  environment=$(grep "ENVIRONMENT ID" $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta | cut -d " " -f 4)
  cluster=$(grep "KAFKA CLUSTER ID" $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta | cut -d " " -f 5)

  if [[ "$OSTYPE" == "darwin"* ]]
  then
      authorization=$(echo -n "$CLOUD_API_KEY:$CLOUD_API_SECRET" | base64)
  else
      authorization=$(echo -n "$CLOUD_API_KEY:$CLOUD_API_SECRET" | base64 -w 0)
  fi
}

function get_sr_url_and_security() {
  get_environment_used


  sr_url="http://localhost:8081"
  sr_security=""

  if [[ "$environment" == "sasl-ssl" ]] || [[ "$environment" == "2way-ssl" ]]
  then
      sr_url="https://localhost:8081"
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      sr_security="--cert $DIR_CLI/../../environment/$environment/security/schema-registry.certificate.pem --key $DIR_CLI/../../environment/$environment/security/schema-registry.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
  elif [[ "$environment" == "rbac-sasl-plain" ]]
  then
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      sr_security="-u superUser:superUser"
  elif [[ "$environment" == "ccloud" ]]
  then
    if [[ ! -n "$root_folder" ]]
    then
      # can happen in filter function where before hook is not called
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
      dir1=$(echo ${DIR_CLI%/*})
      root_folder=$(echo ${dir1%/*})
    fi
    if [ -f $root_folder/.ccloud/env.delta ]
    then
        source $root_folder/.ccloud/env.delta
    else
        logerror "ERROR: $root_folder/.ccloud/env.delta has not been generated"
        exit 1
    fi
    sr_url=$SCHEMA_REGISTRY_URL
    sr_security="-u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"
  fi
}

function get_security_broker() {
  config_file_name="$1"
  get_environment_used


  container="broker"
  security=""
  if [[ "$environment" == "kerberos" ]] || [[ "$environment" == "ssl_kerberos" ]]
  then
      container="client"
      security="$config_file_name /etc/kafka/consumer.properties"

      docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
  elif [ "$environment" == "ldap-authorizer-sasl-plain" ]
  then
      security="$config_file_name /service/kafka/users/kafka.properties"
  elif [ "$environment" == "ldap-sasl-plain" ] || [ "$environment" == "sasl-plain" ] || [ "$environment" == "sasl-scram" ]
  then
      security="$config_file_name /tmp/client.properties"
  elif [[ "$environment" != *plaintext ]]
  then
      security="$config_file_name /etc/kafka/secrets/client_without_interceptors.config"
  fi
}

function get_fzf_version() {
    version=$(fzf --version | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | cut -d " " -f 1)
    echo "$version"
}

function get_examples_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
        res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
    else
      res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
    fi
  else
    res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
  fi
}

function get_examples_list_with_fzf_ccloud_only() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
      res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
    else
      res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
    fi
  else
    res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
  fi
}

function get_examples_list_with_fzf_without_repro() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
      res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
    else
      res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
    fi
  else
    res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
  fi
}

function get_examples_list_with_fzf_without_repro_sink_only() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
      res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
    else
      res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
    fi
  else
    res=$(cat $root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
  fi
}

function get_zip_or_jar_with_fzf() {
  cur="$1"
  type="$2"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  folder_zip_or_jar=$(playground config get folder_zip_or_jar)
  if [ "$folder_zip_or_jar" == "" ]
  then
    logerror "Could not find config value <folder_zip_or_jar> !"
    exit 1
  fi

  folder_zip_or_jar=${folder_zip_or_jar//\~/$HOME}
  folder_zip_or_jar=${folder_zip_or_jar//,/ }
  
  res=$(find $folder_zip_or_jar $PWD -name \*.$type ! -path '*/\.*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_playground_repro_export_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  folder_zip_or_jar=$(playground config get folder_zip_or_jar)
  if [ "$folder_zip_or_jar" == "" ]
  then
    logerror "Could not find config value <folder_zip_or_jar> !"
    exit 1
  fi

  folder_zip_or_jar=${folder_zip_or_jar//\~/$HOME}
  folder_zip_or_jar=${folder_zip_or_jar//,/ }
  
  res=$(find $folder_zip_or_jar $PWD -name playground_repro_export.tgz ! -path '*/\.*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_confluent_kafka_region_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(cat $root_folder/scripts/cli/confluent-kafka-region-list.txt | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_any_files_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(cat $root_folder/scripts/cli/get_any_files_with_fzf | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_predefined_schemas_with_fzf() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})
  predefined_folder=$dir2/scripts/cli/predefined-schemas

  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=70%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    res=$(find $predefined_folder $PWD -maxdepth 2 \( -name "*.json" -o -name "*.avsc" -o -name "*.proto" -o -name "*.proto5" -o -name "*.sql" \) | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
  else
    res=$(find $predefined_folder $PWD -maxdepth 2 \( -name "*.json" -o -name "*.avsc" -o -name "*.proto" -o -name "*.proto5" -o -name "*.sql" \) | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
  fi
}

function get_plugin_list() {
  cur="$1"
  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(cat $root_folder/scripts/cli/confluent-hub-plugin-list.txt | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function filter_not_mdc_environment() {
  get_environment_used


  if [[ "$environment" == "mdc"* ]]
  then
    echo "$environment is not supported with this command !"
  fi
}

function filter_ccloud_environment() {
  get_environment_used

  if [[ "$environment" != "ccloud" ]]
  then
    echo "environment should be ccloud with this command (it is $environment)!"
  fi
}

function filter_schema_registry_running() {
  get_sr_url_and_security

  curl $sr_security -s "${sr_url}/config" > /dev/null 2>&1
  if [ $? != 0 ]
  then
    echo "schema registry rest api should be running to run this command"
  fi
}

function filter_connect_running() {
  get_connect_url_and_security

  curl $security -s "${connect_url}" > /dev/null 2>&1
  if [ $? != 0 ]
  then
    echo "connect rest api should be running to run this command"
  fi
}

function filter_docker_running() {
  docker info >/dev/null 2>&1 || echo "Docker must be running"
}

function increment_cli_metric() {
  metric_name="$1"
  metric=$(playground state get "metrics.$metric_name")
  if [ "$metric" == "" ]
  then
    # initialize
    playground state set "metrics.$metric_name" 1
  else
    playground state set "metrics.$metric_name" $((metric+1))
  fi
}

function get_cli_metric() {
  metric_name="$1"
  playground state get "metrics.$metric_name"
}

function add_connector_config_based_on_environment () {
  environment="$1"
  json_content="$2"

  echo "$json_content" > $tmp_dir/1.json

  case "${environment}" in
    plaintext)
      # nothing to do
      return
    ;;
    ccloud)
      if [ -f $root_folder/.ccloud/env.delta ]
      then
          source $root_folder/.ccloud/env.delta
      else
          logerror "ERROR: $root_folder/.ccloud/env.delta has not been generated"
          exit 1
      fi

      echo "$json_content" > $tmp_dir/input.json
      jq ".[\"topic.creation.default.replication.factor\"] = \"-1\" | .[\"topic.creation.default.partitions\"] = \"-1\"" $tmp_dir/input.json > $tmp_dir/output.json
      json_content=$(cat $tmp_dir/output.json)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.bootstrap.servers\"] = \"\${file:/data:bootstrap.servers}\" | .[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/data:sasl.username}\\\" password=\\\"\${file:/data:sasl.password}\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_SSL\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)

          if [ "$prefix" == "confluent.topic" ]
          then
            echo "$json_content" > $tmp_dir/input.json
            jq ".[\"confluent.topic.replication.factor\"] = \"3\"" $tmp_dir/input.json > $tmp_dir/output.json
            json_content=$(cat $tmp_dir/output.json)
          fi
        fi
      done

      for prefix in {"key","value"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.converter.schema.registry.url\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix.converter.schema.registry.url config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.converter.schema.registry.url\"] = \"$SCHEMA_REGISTRY_URL\" | .[\"$prefix.converter.basic.auth.user.info\"] = \"\${file:/data:schema.registry.basic.auth.user.info}\" | .[\"$prefix.converter.basic.auth.credentials.source\"] = \"USER_INFO\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.kafka.bootstrap.servers\"] = \"\${file:/data:bootstrap.servers}\" | .[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/data:sasl.username}\\\" password=\\\"\${file:/data:sasl.password}\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/data:sasl.username}\\\" password=\\\"\${file:/data:sasl.password}\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.kafka.bootstrap.servers\"] = \"\${file:/data:bootstrap.servers}\" | .[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/data:sasl.username}\\\" password=\\\"\${file:/data:sasl.password}\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/data:sasl.username}\\\" password=\\\"\${file:/data:sasl.password}\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.bootstrap.servers\"] = \"\${file:/data:bootstrap.servers}\" | .[\"reporter.result.topic.replication.factor\"] = \"3\" | .[\"reporter.error.topic.replication.factor\"] = \"3\" | .[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/data:sasl.username}\\\" password=\\\"\${file:/data:sasl.password}\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/data:sasl.username}\\\" password=\\\"\${file:/data:sasl.password}\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    sasl-plain|ldap-authorizer-sasl-plain|ldap-sasl-plain)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    sasl-ssl)
    
      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.bootstrap.servers\"] = \"broker:9092\" | .[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_SSL\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\" | .[\"$prefix.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      for prefix in {"key","value"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.converter.schema.registry.url\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix.converter.schema.registry.url config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.converter.schema.registry.url\"] = \"https://schema-registry:8081\" | .[\"$prefix.converter.schema.registry.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.converter.schema.registry.ssl.truststore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"$prefix.converter.schema.registry.ssl.keystore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.key.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.kafka.bootstrap.servers\"] = \"broker:9092\" | .[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.producer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.kafka.bootstrap.servers\"] = \"broker:9092\" | .[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.producer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.admin.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.admin.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.producer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    2way-ssl)
    
      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.bootstrap.servers\"] = \"broker:9092\" | .[\"$prefix.security.protocol\"] = \"SSL\" | .[\"$prefix.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.ssl.truststore.password\"] = \"confluent\" | .[\"$prefix.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"$prefix.ssl.keystore.password\"] = \"confluent\" | .[\"$prefix.ssl.key.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      for prefix in {"key","value"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.converter.schema.registry.url\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix.converter.schema.registry.url config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.converter.schema.registry.url\"] = \"https://schema-registry:8081\" | .[\"$prefix.converter.schema.registry.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.converter.schema.registry.ssl.truststore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"$prefix.converter.schema.registry.ssl.keystore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.key.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.kafka.bootstrap.servers\"] = \"broker:9092\" | .[\"database.history.producer.security.protocol\"] = \"SSL\" | .[\"database.history.consumer.security.protocol\"] = \"SSL\" | .[\"database.history.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.producer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.producer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"database.history.producer.ssl.keystore.password\"] = \"confluent\" | .[\"database.history.producer.ssl.keystore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.consumer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"database.history.consumer.ssl.keystore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.keystore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.kafka.bootstrap.servers\"] = \"broker:9092\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SSL\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SSL\" | .[\"schema.history.internal.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.producer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.producer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"schema.history.internal.producer.ssl.keystore.password\"] = \"confluent\" | .[\"schema.history.internal.producer.ssl.keystore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.consumer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"schema.history.internal.consumer.ssl.keystore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.keystore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.security.protocol\"] = \"SSL\" | .[\"reporter.admin.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.admin.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.admin.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"reporter.admin.ssl.keystore.password\"] = \"confluent\" | .[\"reporter.admin.ssl.keystore.password\"] = \"confluent\" | .[\"reporter.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.producer.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.producer.security.protocol\"] = \"SSL\" | .[\"reporter.producer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"reporter.producer.ssl.keystore.password\"] = \"confluent\" | .[\"reporter.producer.ssl.keystore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    sasl-scram)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"SCRAM-SHA-256\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"SCRAM-SHA-256\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"SCRAM-SHA-256\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    kerberos)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"GSSAPI\" | .[\"$prefix.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.consumer.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.consumer.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"
        
        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.admin.sasl.kerberos.service.name\"] = \"kafka\" | .[\"reporter.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.producer.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    ssl_kerberos)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_SSL\" | .[\"$prefix.sasl.mechanism\"] = \"GSSAPI\" | .[\"$prefix.sasl.kerberos.service.name\"] = \"kafka\" | .[\"$prefix.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"database.history.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.producer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.consumer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"database.history.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"schema.history.internal.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.producer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.consumer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"schema.history.internal.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"
        
        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.admin.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.admin.sasl.kerberos.service.name\"] = \"kafka\" | .[\"reporter.admin.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.admin.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"reporter.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.producer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    rbac-sasl-plain)

      echo "$json_content" > $tmp_dir/input.json
      jq ".[\"principal.service.name\"] = \"connectorSA\" | .[\"principal.service.password\"] = \"connectorSA\"" $tmp_dir/input.json > $tmp_dir/output.json
      json_content=$(cat $tmp_dir/output.json)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"
        
        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    *)
      return
    ;;
  esac

  echo "$json_content" > $tmp_dir/2.json
  log "✨ Following config was added to handle environment $environment:"
  diff <(jq --sort-keys . $tmp_dir/1.json) <(jq --sort-keys . $tmp_dir/2.json)
}