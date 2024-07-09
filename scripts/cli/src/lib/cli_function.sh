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

function generate_get_examples_add_emoji () {
  repro=""
  if [[ $file_path == *"reproduction-models"* ]]
  then
    repro="🛠"
  fi

  if [[ $file_path == *"ccloud"* ]]
  then
    if [[ $file_path == *"fm-"* ]]
    then
      echo "${repro}🌤️🤖 $file_path" >> $output_file
    elif [[ $file_path == *"custom-connector"* ]]
    then
      echo "${repro}🌤️🛃 $file_path" >> $output_file
    elif [[ $file_path == *"environment"* ]]
    then
      echo "${repro}🌤️🔐 $file_path" >> $output_file
    else
      echo "${repro}🌤️ $file_path" >> $output_file
    fi
  elif [[ $file_path == *"connect"* ]]
  then
    if [[ $file_path == *"sink"* ]]
    then
      echo "${repro}🔗🌎🔹 $file_path" >> $output_file
    elif [[ $file_path == *"source"* ]]
    then
      echo "${repro}🔗🌎🔻 $file_path" >> $output_file
    else
      echo "${repro}🔗🌎 $file_path" >> $output_file
    fi
  elif [[ $file_path == *"ksql"* ]]
  then
    echo "${repro}🎏 $file_path" >> $output_file
  elif [[ $file_path == *"schema-registry"* ]]
  then
    echo "${repro}🔰 $file_path" >> $output_file
  elif [[ $file_path == *"rest-proxy"* ]]
  then
    echo "${repro}😴 $file_path" >> $output_file
  elif [[ $file_path == *"environment"* ]]
  then
    echo "${repro}🔐 $file_path" >> $output_file
  else
    echo "${repro}👾 $file_path" >> $output_file
  fi
}

function generate_fzf_find_files() {
  generate_get_examples_list_with_fzf_without_repro_sink_only
  generate_get_examples_list_with_fzf_without_repro
  generate_get_examples_list_with_fzf_ccloud_only
  generate_get_examples_list_with_fzf

  generate_get_examples_list_with_fzf_connector_only
  generate_get_examples_list_with_fzf_repro_only
  generate_get_examples_list_with_fzf_environemnt_only
  generate_get_examples_list_with_fzf_ksql_only
  generate_get_examples_list_with_fzf_fully_managed_connector_only
  generate_get_examples_list_with_fzf_schema_registry_only
  generate_get_examples_list_with_fzf_rest_proxy_only
  generate_get_examples_list_with_fzf_other_playgrounds_only
}

function generate_get_examples_list_with_fzf_connector_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_connector_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/connect/connect-*/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' ! -path '*/ccloud/*'  | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  sort -o $output_file $output_file
}

function generate_get_examples_list_with_fzf_repro_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_repro_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*'  ! -path '*/security/*' -path '*/reproduction-models/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_environemnt_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_environment_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'update_run.sh' ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/security/*' -path '*/environment/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_ksql_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_ksql_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/ksqldb/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*'  ! -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_fully_managed_connector_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/fm-*/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_schema_registry_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_schema_registry_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/schema-registry/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' ! -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_rest_proxy_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_rest_proxy_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/rest-proxy/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*'  ! -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_other_playgrounds_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_other_playgrounds_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*'  ! -path '*/security/*' ! -path '*/reproduction-models/*'  ! -path '*/ccloud/*' ! -path '*/reproduction-models/*' ! -path '*/connect/*' ! -path '*/ksqldb/*' ! -path '*/schema-registry/*'  | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}


function generate_get_examples_list_with_fzf_without_repro_sink_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/connect-*-sink/*' ! -path '*/scripts/*'  ! -path '*/other/*' ! -path '*/ccloud/*'  ! -path '*/academy/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_without_repro () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_without_repro"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*'  ! -path '*/security/*' ! -path '*/reproduction-models/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_ccloud_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/ccloud*' ! -path '*/security/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_all"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/security/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
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

  if [ -z $CLOUD_API_KEY ]
  then
    logerror "❌ environment variable CLOUD_API_KEY should be set to use $CONNECTOR_TYPE_FULLY_MANAGED or $CONNECTOR_TYPE_CUSTOM connector"
    logerror "Set it with Cloud API key, see https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys"
    exit 1
  fi

  if [ -z $CLOUD_API_SECRET ]
  then
    logerror "❌ environment variable CLOUD_API_SECRET should be set to use $CONNECTOR_TYPE_FULLY_MANAGED or $CONNECTOR_TYPE_CUSTOM connector"
    logerror "Set it with Cloud API secret, see https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys"
    exit 1
  fi
  
  authorization=$(echo -n "$CLOUD_API_KEY:$CLOUD_API_SECRET" | base64)
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
  file="$2"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
        res=$(cat $file | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select example" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "1,-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat /{2..}');echo "$cur@$(echo $res | cut -d ' ' -f 2)"
    else
      res=$(cat $file | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select example" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "1,-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 /{2..}');echo "$cur@$(echo $res | cut -d ' ' -f 2)"
    fi
  else
    res=$(cat $file | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select example" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "1,-3,-2,-1" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$(echo $res | cut -d ' ' -f 2)"
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
    fzf_option_wrap=""
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
  
  res=$(find $folder_zip_or_jar $PWD -name \*.$type ! -path '*/\.*' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🤐" --header="select zip or jar file" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_specific_file_extension() {
  cur="$1"
  extension="$2"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(find $PWD -name \*.$extension ! -path '*/\.*' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔖" --header="select $extension file" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
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
    fzf_option_wrap=""
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
  
  res=$(find $folder_zip_or_jar $PWD -name playground_repro_export.tgz ! -path '*/\.*' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🍺" --header="select repro zip file" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_ccloud_environment_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(confluent environment list | awk -F'|' '{print $2"/"$3}' | sed 's/[[:blank:]]//g' | grep -v "ID" | grep -v "\-\-\-" | grep -v '^/' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌐" --header="select ccloud environment" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_ccloud_cluster_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(confluent kafka cluster list | awk -F'|' '{print $2"/"$3}' | sed 's/[[:blank:]]//g' | grep -v "ID" | grep -v "\-\-\-" | grep -v '^/' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌐" --header="select ccloud cluster" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
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
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(cat $root_folder/scripts/cli/confluent-kafka-region-list.txt | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌍" --header="select region" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function ec2_instance_list() {
  username=$(whoami)
  name="pg-${username}"

  for row in $(aws ec2 describe-instances --filters "Name=tag:Name,Values=$name-*" | jq '[.Reservations | .[] | .Instances | .[] | select(.State.Name!="terminated") | {PublicDnsName: .PublicDnsName, InstanceId: .InstanceId,State: .State.Name, Name: (.Tags[]|select(.Key=="Name")|.Value)}]' | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }

      Name=$(echo $(_jq '.Name'))
      if [[ $Name != $name* ]]
      then
          continue
      fi
      PublicDnsName=$(echo $(_jq '.PublicDnsName'))
      InstanceId=$(echo $(_jq '.InstanceId'))
      State=$(echo $(_jq '.State'))

      if [ "$State" = "stopped" ]
      then
          echo "$Name/$EC2_INSTANCE_STATE_STOPPED/$PublicDnsName/$InstanceId"
      elif [ "$State" = "stopping" ]
      then
          echo "$Name/$EC2_INSTANCE_STATE_STOPPING"
      elif [ "$State" = "pending" ]
      then
          echo "$Name/$EC2_INSTANCE_STATE_PENDING"
      else
          echo "$Name/$EC2_INSTANCE_STATE_RUNNING/$PublicDnsName/$InstanceId"
      fi
  done
}

function get_ec2_instance_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(ec2_instance_list | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🖥️" --header="select ec2 instance (wait for it)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function ec2_cloudformation_list() {
  username=$(whoami)
  name="pg-${username}"

  for row in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE | jq '[.StackSummaries | .[] | {StackName: .StackName,StackStatus: .StackStatus }]' | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }

      StackName=$(echo $(_jq '.StackName'))
      StackStatus=$(echo $(_jq '.StackStatus'))

      if [[ $StackName != $name* ]]
      then
          continue
      fi

      echo "$StackName/$StackStatus"
  done
}

function get_ec2_cloudformation_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(ec2_cloudformation_list | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌀" --header="select ec2 cloudformation (wait for it)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_tag_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(cat $root_folder/scripts/cli/tag-list.txt | sed '1!G;h;$!d' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🎯" --header="select cp version" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
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
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(cat $root_folder/scripts/cli/get_any_files_with_fzf | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📃" --header="select file" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
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
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    res=$(find $predefined_folder -maxdepth 3 \( -name "*.json" -o -name "*.avsc" -o -name "*.proto" -o -name "*.proto5" -o -name "*.sql" \) | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔰" --header="select a predefined schema" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
  else
    res=$(find $predefined_folder -maxdepth 3 \( -name "*.json" -o -name "*.avsc" -o -name "*.proto" -o -name "*.proto5" -o -name "*.sql" \) | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔰" --header="select a predefined schema" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
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
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(cat $root_folder/scripts/cli/confluent-hub-plugin-list.txt | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔌" --header="select connector plugin" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function choose_connector_tag() {
  connector_plugin="$1"

  owner=$(echo "$connector_plugin" | cut -d "/" -f 1)
  name=$(echo "$connector_plugin" | cut -d "/" -f 2)

  filename="/tmp/version_$owner_$name"

  if [ ! -f $filename ]
  then
    playground connector-plugin versions --connector-plugin $owner/$name > /dev/null 2>&1
  fi

  if [ ! -f $filename ]
  then
      logerror "❌ could not get versions for connector plugin $connector_plugin"
      exit 1
  fi


  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  cat $filename | sed '1!G;h;$!d' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔢" --header="select connector version for $owner/$name" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer
}

function filter_not_mdc_environment() {
  get_environment_used


  if [[ "$environment" == "mdc"* ]]
  then
    logerror "$environment is not supported with this command !"
  fi
}

function filter_ccloud_environment() {
  get_environment_used

  if [[ "$environment" != "ccloud" ]]
  then
    logerror "environment should be ccloud with this command (it is $environment)!"
  fi
}

function filter_schema_registry_running() {
  get_sr_url_and_security

  curl $sr_security -s "${sr_url}/config" > /dev/null 2>&1
  if [ $? != 0 ]
  then
    logerror "schema registry rest api should be running to run this command"
  fi
}

function filter_connect_running() {
  get_connect_url_and_security

  curl $security -s "${connect_url}" > /dev/null 2>&1
  if [ $? != 0 ]
  then
    logerror "connect rest api should be running to run this command"
  fi
}

function filter_docker_running() {
  docker info >/dev/null 2>&1 || logerror "docker must be running"
}

function filter_aws_ec2_permissions() {
  aws ec2 describe-instances --dry-run > /tmp/output_ec2_describe_instance.log 2>&1
  if ! grep -q "DryRunOperation" /tmp/output_ec2_describe_instance.log
  then
    logerror "aws ec2 describe-instances command got an error"
    logerror "please make sure to have AdministratorAccess in aws"
    cat /tmp/output_ec2_describe_instance.log
  fi
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

function set_cli_metric() {
  metric_name="$1"
  metric_value="$2"
  playground state set "metrics.$metric_name" "$metric_value"
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
  set +e
  diff <(jq --sort-keys . $tmp_dir/1.json) <(jq --sort-keys . $tmp_dir/2.json)
  set -e
}

function maybe_remove_flag () {
  flag="$1"
  for ((i=0; i<${#array_flag_list[@]}; i++))
  do
    if [[ ${array_flag_list[i]} == ${flag}=* ]]
    then
        unset "array_flag_list[i]"
    fi
  done
}

function display_interactive_menu_categories () {
  repro=$1

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
      fzf_option_wrap="--preview-window=40%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_rounded="--border=rounded"
  else
      fzf_option_pointer=""
      fzf_option_rounded=""
  fi

  if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only ]
  then
    playground generate-fzf-find-files
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    MAX_LENGTH=$((${terminal_columns}-120))
  else
    MAX_LENGTH=$((${terminal_columns}-65))
  fi

  if [ -f $root_folder/scripts/cli/get_examples_list_with_fzf_repro_only ]
  then
    nb_repro=$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_repro_only | awk '{print $1}')
  else
    nb_repro=0
  fi

  MENU_CONNECTOR="🔗 Connectors $(printf '%*s' $((${MAX_LENGTH}-13-${#MENU_CONNECTOR})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_connector_only | awk '{print $1}') examples"
  MENU_CCLOUD="🌤️  Confluent cloud $(printf '%*s' $((${MAX_LENGTH}-18-${#MENU_CCLOUD})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only | awk '{print $1}') examples"
  MENU_FULLY_MANAGED_CONNECTOR="🤖 Fully-Managed connectors $(printf '%*s' $((${MAX_LENGTH}-27-${#MENU_FULLY_MANAGED_CONNECTOR})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only | awk '{print $1}') examples"
  MENU_REPRO="🛠  Reproduction models $(printf '%*s' $((${MAX_LENGTH}-22-${#MENU_REPRO})) ' ') $nb_repro examples"
  MENU_OTHER="👾 Other playgrounds $(printf '%*s' $((${MAX_LENGTH}-20-${#MENU_OTHER})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_other_playgrounds_only | awk '{print $1}') examples"
  MENU_ENVIRONMENTS="🔐 Environments $(printf '%*s' $((${MAX_LENGTH}-15-${#MENU_ENVIRONMENTS})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_environment_only | awk '{print $1}') examples"
  MENU_ALL="🎲 All $(printf '%*s' $((${MAX_LENGTH}-6-${#MENU_ALL})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_all | awk '{print $1}') examples"
  MENU_KSQL="🎏 ksqlDB $(printf '%*s' $((${MAX_LENGTH}-9-${#MENU_KSQL})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_ksql_only | awk '{print $1}') examples"
  MENU_SR="🔰 Schema registry $(printf '%*s' $((${MAX_LENGTH}-18-${#MENU_SR})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_schema_registry_only | awk '{print $1}') examples"
  MENU_RP="🧲 Rest proxy $(printf '%*s' $((${MAX_LENGTH}-13-${#MENU_RP})) ' ') $(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_rest_proxy_only | awk '{print $1}') examples"

  if [ "$repro" == 1 ]
  then
    propose_current_example=0
    set +e
    current_file=$(playground state get run.test_file)
    if [ $? -ne 0 ]
    then
      propose_current_example=0
    fi
    set -e
    if [ -f "$current_file" ]
    then
      last_two_folders=$(basename $(dirname $(dirname $current_file)))/$(basename $(dirname $current_file))
      filename=$(basename $current_file)
      current_file="$last_two_folders/$filename"

      if [[ $current_file != *"reproduction-models"* ]]
      then
        propose_current_example=1
      fi
    fi

    if [ $propose_current_example -eq 1 ]
    then
      MENU_CURRENT_EXAMPLE="🕹️  Current example $(printf '%*s' $((${MAX_LENGTH}-18-${#MENU_CURRENT_EXAMPLE})) ' ') $current_file"
      options=("$MENU_CURRENT_EXAMPLE" "$MENU_CONNECTOR" "$MENU_CCLOUD" "$MENU_FULLY_MANAGED_CONNECTOR" "$MENU_OTHER" "$MENU_ENVIRONMENTS" "$MENU_ALL" "$MENU_KSQL" "$MENU_SR" "$MENU_RP")
    else
      options=("$MENU_CONNECTOR" "$MENU_CCLOUD" "$MENU_FULLY_MANAGED_CONNECTOR" "$MENU_OTHER" "$MENU_ENVIRONMENTS" "$MENU_ALL" "$MENU_KSQL" "$MENU_SR" "$MENU_RP")
    fi
  else
    options=("$MENU_CONNECTOR" "$MENU_CCLOUD" "$MENU_FULLY_MANAGED_CONNECTOR" "$MENU_REPRO" "$MENU_OTHER" "$MENU_ENVIRONMENTS" "$MENU_ALL" "$MENU_KSQL" "$MENU_SR" "$MENU_RP")
  fi

  res=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select a category (ctrl-c or esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_pointer)

  case "${res}" in
    "$MENU_CURRENT_EXAMPLE")
      test_file=$(playground state get run.test_file)
      if [ ! -f $test_file ]
      then
          logerror "❌ file $test_file retrieved from $root_folder/playground.ini does not exist!"
          exit 1
      fi
    ;;
    "$MENU_CONNECTOR")
      test_file=$(playground get-examples-list-with-fzf --connector-only)
    ;;
    "$MENU_CCLOUD")
      test_file=$(playground get-examples-list-with-fzf --ccloud-only)
    ;;
    "$MENU_FULLY_MANAGED_CONNECTOR")
      test_file=$(playground get-examples-list-with-fzf --fully-managed-connector-only)
    ;;
    "$MENU_REPRO")
      test_file=$(playground get-examples-list-with-fzf --repro-only)
    ;;
    "$MENU_ENVIRONMENTS")
      test_file=$(playground get-examples-list-with-fzf --environment-only)
    ;;
    "$MENU_KSQL")
      test_file=$(playground get-examples-list-with-fzf --ksql-only)
    ;;
    "$MENU_SR")
      test_file=$(playground get-examples-list-with-fzf --schema-registry-only)
    ;;
    "$MENU_RP")
      test_file=$(playground get-examples-list-with-fzf --rest-proxy-only)
    ;;
    "$MENU_OTHER")
      test_file=$(playground get-examples-list-with-fzf --other-playgrounds-only)
    ;;
    "$MENU_ALL")
      test_file=$(playground get-examples-list-with-fzf)
    ;;
    *)
      logerror "❌ wrong choice: $res"
      exit 1
    ;;
  esac
}

function cleanup_confluent_cloud_resources () {
  bootstrap_ccloud_environment

  log "🧹 cleanup resources for confluent cloud cluster $CLUSTER_NAME" 

  # for row in $(confluent api-key list --output json | jq -r '.[] | @base64'); do
  #     _jq() {
  #     echo ${row} | base64 -d | jq -r ${1}
  #     }
      
  #     key=$(echo $(_jq '.key'))
  #     resource_type=$(echo $(_jq '.resource_type'))

  #     if [[ $resource_type = cloud ]] && [[ "$key" != "$CLOUD_API_KEY" ]]
  #     then
  #       log "deleting cloud api key $key"
  #       confluent api-key delete $key --force
  #     fi
  # done

  for row in $(confluent connect cluster list --output json | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }
      
      id=$(echo $(_jq '.id'))
      name=$(echo $(_jq '.name'))

      if [[ $name = *_${user}* ]]
      then
          log "deleting connector $id ($name)"
          check_if_skip "confluent connect cluster delete $id --force"
      fi
  done

  for row in $(confluent environment list --output json | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }
      
      id=$(echo $(_jq '.id'))
      name=$(echo $(_jq '.name'))

      if [[ $name = pg-${user}-sa-* ]]
      then
          log "deleting environment $id ($name)"
          check_if_skip "confluent environment delete $id --force"
      fi
  done

  for topic in $(confluent kafka topic list | awk '{if(NR>2) print $1}')
  do
      log "delete topic $topic"
      check_if_skip "confluent kafka topic delete \"$topic\" --force"
  done

  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
    for subject in $(curl -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL/subjects" | jq -r '.[]')
    do
        log "permanently delete subject $subject"
        check_if_skip "curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject\" && curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject?permanent=true\""
    done

    for row in $(confluent iam service-account list --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 -d | jq -r ${1}
        }
        
        description=$(echo $(_jq '.description'))
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        log "deleting service-account $id ($description)"
        check_if_skip "confluent iam service-account delete $id --force"
    done
  fi
}

function get_zazkia_id_list () {
  handle_onprem_connect_rest_api "curl -s -X GET -H \"Content-Type: application/json\" \"http://localhost:9191/links/\""
  if [[ $(echo "$curl_output" | jq -r '.[].links[]') != "" ]]
  then
    echo "$curl_output" | jq -r '.[].links[] | select(.serviceReceiveError != "EOF") | .id' | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'
  else
    echo ""
  fi
}

function wait_for_ec2_instance_to_be_running () {
  instance="$1"
  max_wait=${2:-300}
  cur_wait=0
  log "⌛ waiting up to $max_wait seconds for ec2 instance $instance to be running"
  playground ec2 status --instance "$instance" > /tmp/out.txt 2>&1
  while ! grep "running" /tmp/out.txt > /dev/null;
  do
    sleep 10
    playground ec2 status --instance "$instance" > /tmp/out.txt 2>&1
    status=$(cat /tmp/out.txt)
    log "⌛ current status: $status"
    cur_wait=$(( cur_wait+10 ))
    if [[ "$cur_wait" -gt "$max_wait" ]]
    then
      logerror "❌ ec2 instance $instance is still not running after $max_wait seconds"
      return 1
    fi
  done
  log "🟢 ec2 instance $instance is running"
}

function wait_for_ec2_cloudformation_to_be_completed () {
  stack_name="$1"
  max_wait=${2:-900}
  cur_wait=0
  log "⌛ waiting up to $max_wait seconds for ec2 cloudformation stack $stack_name to be in status CREATE_COMPLETE"
  log "⌛ you can check progress by checking log file output.log in root folder of ec2 instance"

  aws cloudformation describe-stacks --output text --query "Stacks[?StackName==\`$stack_name\`].StackStatus" > /tmp/out.txt 2>&1
  while ! grep "CREATE_COMPLETE" /tmp/out.txt > /dev/null;
  do
    sleep 10
    aws cloudformation describe-stacks --output text --query "Stacks[?StackName==\`$stack_name\`].StackStatus" > /tmp/out.txt 2>&1
    status=$(cat /tmp/out.txt)
    log "⌛ current status: $status"

    if grep "CREATE_FAILED" /tmp/out.txt > /dev/null;
    then
      logerror "❌ ec2 cloudformation stack $stack_name is in state $status"
      logerror "❌ check log file output.log in root folder of ec2 instance for troubleshooting the issue"
      return 1
    fi

    if grep "ROLLBACK_" /tmp/out.txt > /dev/null;
    then
      logerror "❌ ec2 cloudformation stack $stack_name is in state $status"
      logerror "❌ check log file output.log in root folder of ec2 instance for troubleshooting the issue"
      return 1
    fi

    cur_wait=$(( cur_wait+10 ))
    if [[ "$cur_wait" -gt "$max_wait" ]]
    then
      logerror "❌ ec2 cloudformation $stack_name is still not in status CREATE_COMPLETE after $max_wait seconds"
      logerror "❌ check log file output.log in root folder of ec2 instance for troubleshooting the issue"
      return 1
    fi
  done
  log "🟢 ec2 cloudformation $stack_name is in status CREATE_COMPLETE"
}

function add_ec2_instance_to_running_list() {
  instance="$1"
  current_list=$(playground state get "ec2.running_list")
  # list can be separated with |
  if [[ "$current_list" == "" ]]
  then
    playground state set "ec2.running_list" "$instance"
  else
    # make sure insance is not already in the list
    if [[ "$current_list" != *"$instance"* ]]
    then
      playground state set "ec2.running_list" "$current_list|$instance"
    fi
  fi
}

function remove_ec2_instance_from_running_list() {
  instance="$1"
  current_list=$(playground state get "ec2.running_list")
  # list can be separated with |
  if [[ "$current_list" != "" ]]
  then
    # make sure insance is not already in the list
    if [[ "$current_list" == *"$instance"* ]]
    then
      new_list=$(echo "$current_list" | sed -e "s/$instance//g" | sed -e 's/||/|/g' | sed -e 's/|$//')
      playground state set "ec2.running_list" "$new_list"
    fi
  fi
}

function check_for_ec2_instance_running() {
  # echo the name of ec2 instance running
  current_list=$(playground state get "ec2.running_list")
  if [[ "$current_list" != "" ]]
  then
    # loop through the list
    for instance in $(echo $current_list | tr "|" "\n")
    do
      log "🤑👛 you have an ec2 instance $instance running"
    done
  fi
}