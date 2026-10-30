IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

test_file="${args[--file]}"
description="${args[--description]}"
producer="${args[--producer]}"
nb_producers="${args[--nb-producers]}"
add_custom_smt="${args[--custom-smt]}"

eval "pipeline_array=(${args[--pipeline]})"

eval "connector_plugin_array=(${args[--connector-plugin]})"

no_run="${args[--no-run]}"
schema_file_key="${args[--producer-schema-key]}"
schema_file_value="${args[--producer-schema-value]}"
expected="${args[--expected]}"
actual="${args[--actual]}"
jira="${args[--jira]}"
config_file="${args[--config]}"
config_connector="${args[--config-connector]}"

# optional fields of the header, asked right after the description in interactive mode (enter or esc to skip)
function prompt_header_field () {
  local header="$1"
  set +e
  echo "" | fzf --margin=1%,1%,1%,1% --info=inline --cycle --prompt="💭 " --header="$header (optional, enter to skip)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --print-query 2>/dev/null | head -1
  set -e
}

function prompt_header_fields () {
  if [ -z "$expected" ]
  then
    expected=$(prompt_header_field "🎯 expected behaviour, for example: records with a bad schema go to the DLQ")
  fi
  if [ -z "$actual" ]
  then
    actual=$(prompt_header_field "💥 actual behaviour, for example: the task fails with Unknown magic byte")
  fi
}

# interactive mode: start from an example, or from the connector config the customer sent
if [ -z "$test_file" ] && [ -z "$config_file" ] && [ -t 0 ] && [ -t 1 ]
then
  MENU_START_FROM_EXAMPLE="🔖 Start from an example"
  MENU_START_FROM_CONFIG="📄 Start from the connector config the customer sent (CFK, Strimzi, terraform, .properties, REST dump, JSON)"
  set +e
  start_from=$(printf '%s\n' "$MENU_START_FROM_EXAMPLE" "$MENU_START_FROM_CONFIG" | fzf --margin=1%,1%,1%,1% --info=inline --cycle --prompt="🛠 " --header="how do you want to start the reproduction model? (esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE")
  if [ $? -ne 0 ]
  then
    exit 0
  fi
  set -e
  if [ "$start_from" == "$MENU_START_FROM_CONFIG" ]
  then
    config_file=$(playground get-connector-config-file-with-fzf)
    config_file="${config_file#*@}"
    if [ -z "$config_file" ]
    then
      exit 0
    fi
  fi
fi

# --config: the connector config the customer sent, in any format of 'playground connector convert'
config_class=""
if [ -n "$config_file" ]
then
  config_file="${config_file#@}"
  if [ ! -f "$config_file" ]
  then
    logerror "❌ --config file $config_file not found"
    exit 1
  fi
  # the script changes directory later
  config_file="$(cd "$(dirname "$config_file")" && pwd)/$(basename "$config_file")"
  if ! normalize_connector_config "$(cat "$config_file")" "$config_connector" "auto"
  then
    logerror "❌ --config $config_file: $NORMALIZED_ERROR"
    exit 1
  fi
  config_class=$(echo "$NORMALIZED_CONFIG" | jq -r '."connector.class" // empty')
  log "📄 --config: $NORMALIZED_FORMAT, connector ${NORMALIZED_NAME:-without name}, connector.class ${config_class:-not set}"
  # converted before any file of the model is written: a config that can't be converted leaves nothing behind
  config_tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
  trap 'rm -rf $config_tmp_dir' EXIT
  if ! playground connector convert "$config_file" --json --secrets-as-variables ${config_connector:+--connector "$config_connector"} > $config_tmp_dir/converted.json 2> $config_tmp_dir/convert.log || ! jq -e '.config | type == "object"' $config_tmp_dir/converted.json > /dev/null 2>&1
  then
    # convert prints its errors on stdout
    cat $config_tmp_dir/convert.log
    grep -v '^[{}" ]' $config_tmp_dir/converted.json || true
    logerror "❌ could not convert $config_file with 'playground connector convert $config_file --json --secrets-as-variables${config_connector:+ --connector $config_connector}'"
    exit 1
  fi
  # the same without the rewrites for the playground, to know which values point to the playground already
  playground connector convert "$config_file" --json --no-adapt ${config_connector:+--connector "$config_connector"} > $config_tmp_dir/raw.json 2> /dev/null || echo '{"config": {}}' > $config_tmp_dir/raw.json
  if [ -z "$test_file" ]
  then
    if [ -z "$config_class" ]
    then
      logerror "❌ the config has no connector.class to find the example to start from: use --file (-f)"
      exit 1
    fi
    candidates=$(repro_base_example_candidates "$NORMALIZED_CONFIG")
    if [ -z "$candidates" ]
    then
      logerror "❌ no example deploys $config_class: use --file (-f) with the closest one (playground find-example \"<connector> <feature>\")"
      exit 1
    fi
    if [ -z "$no_run" ] && [ -t 0 ] && [ -t 1 ] && [ $(echo "$candidates" | wc -l) -gt 1 ]
    then
      set +e
      picked=$(echo "$candidates" | head -20 | fzf --margin=1%,1%,1%,1% --info=inline --cycle --prompt="🔖 " --header="examples that deploy $config_class, best first: pick the one to start from (esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE")
      if [ $? -ne 0 ]
      then
        exit 0
      fi
      set -e
    else
      picked=$(echo "$candidates" | head -1)
      log "🔖 example to start from: $picked (-f to pick another one)"
      if [ $(echo "$candidates" | wc -l) -gt 1 ]
      then
        log "   other examples that deploy $config_class:"
        echo "$candidates" | sed -n '2,6p' | sed 's/^/     /'
      fi
    fi
    test_file="$root_folder/$picked"
  fi
fi

if [[ ! -n "$test_file" ]]
then
  display_interactive_menu_categories 1

  if [[ $test_file == *"@"* ]]
  then
    test_file=$(echo "$test_file" | cut -d "@" -f 2)
  fi

  declare -a array_flag_list=()
  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    MAX_LENGTH=$((${terminal_columns}-120))
    fzf_version=$(get_fzf_version)
    if version_gt $fzf_version "0.38"
    then
      fzf_option_wrap="--preview-window=30%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_empty_pointer=""
      fzf_option_rounded="--border=rounded"
    else
      fzf_option_wrap=""
      fzf_option_pointer=""
      fzf_option_empty_pointer=""
      fzf_option_rounded=""
    fi
  else
    MAX_LENGTH=$((${terminal_columns}-65))
    fzf_version=$(get_fzf_version)
    if version_gt $fzf_version "0.38"
    then
      fzf_option_wrap="--preview-window=20%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_empty_pointer=""
      fzf_option_rounded="--border=rounded"
    else
      fzf_option_wrap=""
      fzf_option_pointer=""
      fzf_option_empty_pointer=""
      fzf_option_rounded=""
    fi
  fi
  readonly MENU_LETS_GO="🏭 Create the reproduction model !"

  MENU_ENABLE_CUSTOM_SMT="$(menu_label "🔧" "Add custom SMT" "--custom-smt")"
  MENU_ADD_CONNECTOR_PLUGIN="$(menu_label "🔌" "Add connector plugin" "--connector-plugin")"

  readonly MENU_DISABLE_CUSTOM_SMT="❌🔧 Disable custom SMT"
  readonly MENU_GO_BACK="🔙 Go back"

  last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
  example="$last_two_folders/$(basename "$test_file")"

  connector_example=0
  get_connector_paths
  if [ "$connector_paths" != "" ]
  then
    for connector_path in ${connector_paths//,/ }
    do
      full_connector_name=$(basename "$connector_path")
      owner=$(echo "$full_connector_name" | cut -d'-' -f1)
      name=$(echo "$full_connector_name" | cut -d'-' -f2-)

      if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
      then
        # happens when plugin is not coming from confluent hub
        continue
      else
        connector_example=1
      fi
    done
  fi

  stop=0
  description=""
  while [ $stop != 1 ]
  do
    length=${#pipeline_array[@]}
    if ((length > 0))
    then
      MENU_PIPELINE="$(menu_label "🔖" "Add another sink to pipeline" "--pipeline")"
    else
      MENU_PIPELINE="$(menu_label "🔖" "Create pipeline with sink" "--pipeline")"
    fi

    # an entry is only added when it applies to this example
    options=("$MENU_LETS_GO")
    if [ $connector_example == 1 ]
    then
      if [[ $test_file != *"sink"* ]]
      then
        options+=("$MENU_PIPELINE")
      fi
      if [ -z "$CUSTOM_SMT" ]
      then
        options+=("$MENU_ENABLE_CUSTOM_SMT")
      else
        options+=("$MENU_DISABLE_CUSTOM_SMT")
      fi
      options+=("$MENU_ADD_CONNECTOR_PLUGIN")
    fi
    options+=("$MENU_GO_BACK")

    if [ "$description" == "" ]
    then
      maybe_remove_flag "--description"
      set +e
      description=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="💭 " --header="enter a description for this repro model (it cannot be empty !, esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
      if [ $? -eq 130 ]
      then
        # esc
        exit 0
      fi
      set -e
      if [ "$description" == "" ]
      then
        continue
      fi
      array_flag_list+=("--description=$description")
      prompt_header_fields
      [ -n "$expected" ] && array_flag_list+=("--expected=$expected")
      [ -n "$actual" ] && array_flag_list+=("--actual=$actual")
    fi

    oldifs=$IFS
    IFS=$'\n' flag_string="${array_flag_list[*]}"
    IFS=$oldifs
    res=$(printf '%s\n' "${options[@]}" | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🛠 " --header="select option(s) for $example (use tab to select more than one)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --preview "echo -e \"👷 Number of repro models created so far: $(get_cli_metric nb_reproduction_models)\n\n🛠️  Number of repro models available: $(get_cli_metric nb_existing_reproduction_models)\n\n⛳ flag list:\n$flag_string\"")

    if [[ $res == *"$MENU_LETS_GO"* ]]
    then
      stop=1
    fi

    if [[ $res == *"$MENU_GO_BACK"* ]]
    then
      playground repro bootstrap
      exit $?
    fi

    if [[ $res == *"$MENU_ENABLE_CUSTOM_SMT"* ]]
    then
      array_flag_list+=("--custom-smt")
      export CUSTOM_SMT=true
      add_custom_smt="true"
    fi
    if [[ $res == *"$MENU_DISABLE_CUSTOM_SMT"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--custom-smt"}")
      unset CUSTOM_SMT
      add_custom_smt=""
    fi

    if [[ $res == *"$MENU_ADD_CONNECTOR_PLUGIN"* ]]
    then
      set +e
      selected_plugin=$(playground get-connector-plugin | head -1)
      if [[ $selected_plugin == *"@"* ]]
      then
        selected_plugin=$(echo "$selected_plugin" | cut -d "@" -f 2)
        connector_plugin_array+=("$selected_plugin")
      fi
      set -e
    fi

    if [[ $res == *"$MENU_PIPELINE"* ]]
    then
      sink_file=$(playground get-examples-list-with-fzf --without-repro --sink-only )
      if [[ $sink_file == *"@"* ]]
      then
        sink_file=$(echo "$sink_file" | cut -d "@" -f 2)
      fi
      array_flag_list+=("--pipeline=$sink_file")
      pipeline_array+=("$sink_file")
    fi
  done # end while loop stop
fi

if [ "$description" == "" ]
then
  # -f without -d (for example the 🧪 entry of the playground run menu)
  set +e
  description=$(echo "" | fzf --margin=1%,1%,1%,1% --info=inline --cycle --prompt="💭 " --header="enter a description for this repro model (it cannot be empty !, esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --print-query 2>/dev/null)
  if [ $? -eq 130 ]
  then
    # esc
    exit 0
  fi
  set -e
  if [ "$description" == "" ]
  then
    logerror "❌ a description is required, use --description (-d)"
    exit 1
  fi
  prompt_header_fields
fi

if [[ $test_file == *"@"* ]]
then
  test_file=$(echo "$test_file" | cut -d "@" -f 2)
fi

if [[ "$test_file" != *".sh" ]]
then
  logerror "❌ test_file $test_file is not a .sh file!"
  exit 1
fi

if [[ "$(dirname $test_file)" != /* ]]
then
  logerror "❌ do not use relative path for test file!"
  exit 1
fi

if [ "$nb_producers" == "" ]
then
  nb_producers=1
fi

if [[ -n "$schema_file_key" ]]
then
  if [ "$producer" == "none" ]
  then
    logerror "❌ --producer-schema-key is set but not --producer"
    exit 1
  fi

  if [[ "$producer" != *"with-key" ]]
  then
    logerror "❌ --producer-schema-key is set but --producer is not set with <with-key>"
    exit 1
  fi
fi

if [[ -n "$schema_file_value" ]]
then
  if [ "$producer" == "none" ]
  then
    logerror "❌ --producer-schema-value is set but not --producer"
    exit 1
  fi
fi

test_file_directory="$(dirname "${test_file}")"
cd ${test_file_directory}

topic_name="customer-$producer"
topic_name=$(echo $topic_name | tr '-' '_')
filename=$(basename -- "$test_file")
extension="${filename##*.}"
filename="${filename%.*}"

base1="${test_file_directory##*/}" # connect-cdc-oracle12-source
dir1="${test_file_directory%/*}" #connect
dir2="${dir1##*/}/$base1" # connect/connect-cdc-oracle12-source
final_dir=$(echo $dir2 | tr '/' '-') # connect-connect-cdc-oracle12-source

length=${#pipeline_array[@]}
if ((length > 0))
then
  if [[ "$base1" != *source ]]
  then
    logerror "example <$base1> must be source connector example when building a pipeline !"
    exit 1
  fi

  if [[ "$dir2" != connect* ]]
  then
    logerror "example <$dir2> is not from connect folder, only connect in connect folder are supported"
    exit 1
  fi
fi

if [ "$producer" != "none" ]
then
  if [[ "$base1" != *sink ]]
  then
    logerror "example <$base1> must be sink connector example when using a java producer !"
    exit 1
  fi
fi

if [ ! -z "$OUTPUT_FOLDER" ]
then
  output_folder="$OUTPUT_FOLDER"
  log "📂 Output folder is $output_folder (set with OUTPUT_FOLDER environment variable)"
else
  output_folder="reproduction-models"
  log "📂 Output folder is default $output_folder (you can change it by setting OUTPUT_FOLDER environment variable)"
fi

repro_dir=$root_folder/$output_folder/$final_dir
mkdir -p $repro_dir
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir $config_tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

description_kebab_case="${description// /-}"
description_kebab_case=$(echo "$description_kebab_case" | tr '[:upper:]' '[:lower:]')
# only keep alphanumeric characters and hyphens
description_kebab_case=$(echo "$description_kebab_case" | tr -cd '[:alnum:]-')
repro_test_file="$repro_dir/$filename-repro-$description_kebab_case.$extension"

# determining the docker-compose file from from test_file
docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
docker_compose_file="${test_file_directory}/${docker_compose_file}"

log "✨ Creating file $repro_test_file"
rm -f $repro_test_file
cp $test_file $repro_test_file

if [ "${docker_compose_file}" != "" ] && [ ! -f "${docker_compose_file}" ]
then
  set +e
  grep 'DOCKER_COMPOSE_FILE_OVERRIDE=$1' "$test_file"
  if [ $? -eq 0 ]
  then
    # it means it is an environment example
    # need to create the docker-compose file
    docker_compose_file=""
    docker_compose_test_file="$repro_dir/docker-compose.repro-$description_kebab_case.yml"
    log "✨ Creating empty file $docker_compose_test_file"

    echo "---" > $docker_compose_test_file
    echo "" >> $docker_compose_test_file
    echo "# override the services here, example " >> $docker_compose_test_file
    echo "# services:" >> $docker_compose_test_file
    echo "#    connect:" >> $docker_compose_test_file
    echo "#      environment:" >> $docker_compose_test_file
    echo "#        CONNECT_BOOTSTRAP_SERVERS: \"broker:9092\"" >> $docker_compose_test_file

    docker_compose_test_file_name=$(basename -- "$docker_compose_test_file")
    cp $test_file $tmp_dir/tmp_file
    line=$(grep -n 'DOCKER_COMPOSE_FILE_OVERRIDE=$1' $test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line-1)) $tmp_dir/tmp_file; echo "DOCKER_COMPOSE_FILE_OVERRIDE=../../$output_folder/$final_dir/$docker_compose_test_file_name"; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $repro_test_file
  else
    docker_compose_file=""
    logwarn "📁 Could not determine docker-compose override file from $test_file !"
  fi
  set -e
fi

if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
then
  filename=$(basename -- "${docker_compose_file}")
  extension="${filename##*.}"
  filename="${filename%.*}"

  docker_compose_test_file="$repro_dir/$filename.repro-$description_kebab_case.$extension"
  log "✨ Creating file $docker_compose_test_file"
  rm -f $docker_compose_test_file
  cp ${docker_compose_file} $docker_compose_test_file

  docker_compose_test_file_name=$(basename -- "$docker_compose_test_file")

    length=${#connector_plugin_array[@]}
    if ((length > 0))
    then
        for selected_plugin in "${connector_plugin_array[@]}"; do
            vendor=$(echo "$selected_plugin" | cut -d'/' -f1)
            plugin_name=$(echo "$selected_plugin" | cut -d'/' -f2)
            selected_plugin="/usr/share/confluent-hub-components/$vendor-$plugin_name"
            test_file_directory="$(dirname "${test_file}")"

            # Check if CONNECT_PLUGIN_PATH already exists
            if grep -q "CONNECT_PLUGIN_PATH" "$docker_compose_file"
            then
                yq -i '.services.connect.environment.CONNECT_PLUGIN_PATH |= . + "," + "'$selected_plugin'"' "$docker_compose_test_file"
            else
                # Add CONNECT_PLUGIN_PATH to connect service environment
                yq -i '.services.connect.environment.CONNECT_PLUGIN_PATH = "'$selected_plugin'"' "$docker_compose_test_file"
            fi

            log "✅🔌 Connector plugin $selected_plugin added to docker-compose file $docker_compose_file"
        done
    fi

fi

if [ "${docker_compose_file}" != "" ]
then
  filename=$(basename -- "${docker_compose_file}")
  sed -e "s|$filename|$docker_compose_test_file_name|g" \
    $test_file > $repro_test_file
fi

set +e
echo "#!/bin/bash" > $tmp_dir/intro
echo "###############################################" >> $tmp_dir/intro
echo "# 🗓️ date: `date`" >> $tmp_dir/intro
echo "# 👤 author: `whoami`" >> $tmp_dir/intro
echo "# 💡 description: $description" >> $tmp_dir/intro
if [[ $description =~ ^[0-9]{6} ]]
then
  numbers="${BASH_REMATCH[0]}"
  echo "# 🔮 ticket: https://confluent.zendesk.com/agent/tickets/$numbers" >> $tmp_dir/intro
fi
echo "# 🙋 how to use: https://github.com/confluentinc/kafka-docker-playground-internal/tree/master#how-to-use" >> $tmp_dir/intro
if [ -z "$OUTPUT_FOLDER" ] || [ "$OUTPUT_FOLDER" == "reproduction-models" ]
then
  last_folder=$(basename $(dirname $repro_test_file))
  f=$(basename $repro_test_file)
  echo "# 🔗 github file url: https://github.com/confluentinc/kafka-docker-playground-internal/blob/master/$last_folder/$f" >> $tmp_dir/intro
fi
string=$(grep "Quickly test " README.md)
url=$(echo "$string" | grep -oE 'https?://[^ ]+')
url=${url//)/}

if [[ $url =~ "http" ]]
then
  short_url=$(echo $url | cut -d '#' -f 1)
  echo "# 🌐 documentation: $short_url" >> $tmp_dir/intro
fi
echo "# 🐳 playground website: https://kafka-docker-playground.io" >> $tmp_dir/intro
echo "# 💬 comments:" >> $tmp_dir/intro
# fields read by 'playground repro status' and 'repro export': fill them in, keep one line each
expected="${expected//$'\n'/ }"
actual="${actual//$'\n'/ }"
echo "# 🎯 expected:${expected:+ $expected}" >> $tmp_dir/intro
echo "# 💥 actual:${actual:+ $actual}" >> $tmp_dir/intro
jira=$(repro_jira_url "$jira")
echo "# 🎫 jira:${jira:+ $jira}" >> $tmp_dir/intro
echo "# 🩹 status: open" >> $tmp_dir/intro
echo "#" >> $tmp_dir/intro
echo "###############################################" >> $tmp_dir/intro
echo "" >> $tmp_dir/intro

cat $tmp_dir/intro > $tmp_dir/tmp_file
cat $repro_test_file | grep -v "#!/bin/bash" >> $tmp_dir/tmp_file
mv $tmp_dir/tmp_file $repro_test_file

if [ -n "$config_file" ]
then
  # the customer config, adapted to the playground (as 'playground connector convert' does), its secrets, masked
  # values and config providers as variables to fill in
  # what convert says about the rewrites for the playground; the values still pointing to the customer and the secrets
  # are handled below
  hide='🌍|🔐|📦 detected|value[(]s[)] to fill in'
  if [[ "$test_file" == */ccloud/* ]]
  then
    # the fully managed config goes in a fully managed example, as it should
    hide="$hide|☁️"
  fi
  awk -v hide="$hide" '$0 ~ hide { skip = 1; next } /^[^ ]/ { skip = 0 } !skip' $config_tmp_dir/convert.log

  # the connector heredoc of the example that deploys the same connector.class (else the first one): first and last line
  location=$(REPRO_CLASS="$config_class" awk '
    BEGIN { cls = ENVIRON["REPRO_CLASS"] }
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (lines[i] !~ /playground connector create-or-update/ || lines[i] !~ /<</) continue
        delim = lines[i]; sub(/.*<<-?[ \t]*/, "", delim); gsub(/["\047]/, "", delim); sub(/[ \t].*/, "", delim)
        for (j = i + 1; j <= NR; j++) { l = lines[j]; gsub(/^[ \t]+|[ \t]+$/, "", l); if (l == delim) break }
        if (j > NR) continue
        if (!first) { first = i " " j }
        if (cls != "" && !found) for (k = i; k <= j; k++) if (index(lines[k], "\"connector.class\"") && index(lines[k], "\"" cls "\"")) { found = i " " j; break }
        i = j
      }
      if (found) print found; else if (first) print first
    }' $repro_test_file)
  start=${location% *}
  end=${location#* }

  # "key": value lines of the example config, the value as written (it can use variables of the example)
  echo '{}' > $tmp_dir/example.json
  if [ -n "$location" ]
  then
    sed -n "$((start + 1)),$((end - 1))p" $repro_test_file \
      | sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*(.*[^,[:space:]])[[:space:]]*,?[[:space:]]*$/\1\t\2/p' \
      | jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1:] | join("\t"))}) | from_entries' > $tmp_dir/example.json
  fi

  # the keys that point to systems (hosts, urls, credentials, cloud locations, topics) keep the value of the example,
  # that the rest of the scenario uses; the others (the behaviour) come from the customer. The name is left out: the
  # connector keeps the name of the example
  system_keys='(^|\.)(connection\.(url|uri|user|username|password|host|hostname|port|database|dbname)|url|urls|uri|host|hosts|hostname|port|endpoint|server|servers|user|username|password|database|db|bucket|bucket\.name|region|account\.name|container\.name|project|dataset|keyfile|credentials|credentials\.json|instance|file|sid|pdb\.name|service\.name|database\.(hostname|port|user|password|dbname|names|server\.name)|topics|topics\.regex|topic|topic\.prefix|topic\.name\.prefix|kafka\.topic|access\.key\.id|secret\.access\.key|secret|api\.key|api\.secret|kafka\.auth\.mode|kafka\.service\.account\.id)$|^(table\.topic\.name\.template|lob\.topic\.name\.template|redo\.log\.topic\.name|topic\.creation\.redo\.include)$|replication\.factor$|(password|secret|jaas|token|credential|api[._]key|private[._]key|access[._]key|user\.info)'
  # the tables (collections, schemas) captured are the ones of the customer database: the scenario creates its own and
  # inserts into them, so the selection of the example is kept, and the one of the customer is left out when the example
  # captures everything
  selection_keys='^((table|database|schema|collection)\.(include|exclude)\.list|table\.(inclusion|exclusion)\.regex|(table|database|schema|collection)\.(whitelist|blacklist))$'
  system_keys="$system_keys|$selection_keys"
  kept=$(jq -r --slurpfile example $tmp_dir/example.json --arg system_keys "$system_keys" '
    [$example[0] | keys_unsorted[] | select(test($system_keys; "i"))] | join(" ")' $config_tmp_dir/converted.json)
  # the customer keys that point to systems the example does not use (connection.user when the example puts the user
  # in the url…) are left out, and so is the topic selection when the example has one (topics and topics.regex can't
  # be both set); the values rewritten for the playground (schema registry url…) stay
  dropped=$(jq -r --slurpfile example $tmp_dir/example.json --slurpfile raw $config_tmp_dir/raw.json --arg system_keys "$system_keys" '
    .config as $config
    | ($example[0] | has("topics") or has("topics.regex")) as $example_topics
    | [$config | keys_unsorted[]
        | select(test($system_keys; "i"))
        | select((test("^topics(\\.regex)?$") | not) or $example_topics)
        | select(. as $k | $example[0] | has($k) | not)
        | select(. as $k | $raw[0].config[$k] == $config[$k])] | join(" ")' $config_tmp_dir/converted.json)
  jq -r --slurpfile example $tmp_dir/example.json --arg system_keys "$system_keys" --arg dropped " $dropped " '
    def system_key: test($system_keys; "i");
    $example[0] as $example
    | (.config | del(.name) | with_entries(.key as $k | select($dropped | contains(" " + $k + " ") | not))) as $config
    | ([.to_fill_in[].key]) as $fill
    | ($example | with_entries(select(.key | system_key))) as $kept
    | ([$config | keys_unsorted[]] + ([$kept | keys_unsorted[]] - [$config | keys_unsorted[]])) as $all
    | [ $all[] as $k
        | (if ($kept | has($k)) then $kept[$k]
           elif ($fill | index($k)) then "\"${" + ($k | ascii_upcase | gsub("[^A-Z0-9]"; "_")) + "}\""
           # an unquoted heredoc: \, $ and ` of the customer values are escaped
           else ($config[$k] | tostring | tojson | gsub("\\\\"; "\\\\") | gsub("\\$"; "\\$") | gsub("`"; "\\`")) end) as $v
        | "  " + ($k | tojson) + ": " + $v ]
    | ((.[:-1] | map(. + ",")) + .[-1:]) as $lines
    | "{", $lines[], "}"' $config_tmp_dir/converted.json > $tmp_dir/config_lines
  # the values to fill in that the example does not provide
  jq -r --arg skip " $kept $dropped " '.to_fill_in[] | .key as $k | select($skip | contains(" " + $k + " ") | not) | "\(.key)|\(.reason)"' $config_tmp_dir/converted.json > $tmp_dir/to_fill

  {
    echo "# 📄 connector config from $(basename "$config_file") ($(jq -r '.detected_format' $config_tmp_dir/converted.json)), put in by 'playground repro bootstrap --config'"
    if [ -n "$kept" ]
    then
      echo "#    values of the example kept, they point to its systems: $kept"
    fi
    if [ -n "$dropped" ]
    then
      echo "#    left out, they point to systems of the customer the example does not use: $dropped"
    fi
    while IFS='|' read -r key reason
    do
      echo "#    to fill in: $key ($reason)"
    done < $tmp_dir/to_fill
    if [ -n "$location" ]
    then
      # the command line of the example (its --connector, --level…)
      prefix=$(sed -n "${start}p" $repro_test_file | sed -E 's/[[:space:]]*<<.*//')
      echo "$prefix << EOF"
    else
      echo "playground connector create-or-update --connector $(jq -r '.name // "my-connector"' $config_tmp_dir/converted.json) << EOF"
    fi
    cat $tmp_dir/config_lines
    echo "EOF"
  } > $tmp_dir/block

  if [ -n "$location" ]
  then
    { sed -n "1,$((start - 1))p" $repro_test_file; cat $tmp_dir/block; sed -n "$((end + 1)),\$p" $repro_test_file; } > $tmp_dir/tmp_file
    mv $tmp_dir/tmp_file $repro_test_file
    log "📄 the connector config of the example is replaced with the one of $(basename "$config_file")"
    [ -n "$kept" ] && log "   values of the example kept (they point to its systems): $kept"
    [ -n "$dropped" ] && log "   left out (systems of the customer the example does not use): $dropped"
  else
    cat $tmp_dir/block >> $repro_test_file
    logwarn "📄 no 'playground connector create-or-update' heredoc in the example: the config of $(basename "$config_file") is added at the end of the scenario"
  fi

  # the values to fill in are checked with the standard message, so that 'playground run' loads them from the
  # 'playground secrets' store
  if [ -s $tmp_dir/to_fill ]
  then
    : > $tmp_dir/checks
    while IFS='|' read -r key reason
    do
      variable=$(echo "$key" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]/_/g')
      printf 'if [ -z "$%s" ]\nthen\n     logerror "%s is not set. Export it as environment variable or pass it as argument"\n     exit 1\nfi\n' "$variable" "$variable" >> $tmp_dir/checks
    done < $tmp_dir/to_fill
    awk -v checks="$tmp_dir/checks" '{ print } !done && /^source .*scripts\/utils\.sh/ { print ""; while ((getline l < checks) > 0) print l; done = 1 }' $repro_test_file > $tmp_dir/tmp_file
    mv $tmp_dir/tmp_file $repro_test_file
    logwarn "🔐 $(grep -c . $tmp_dir/to_fill) value(s) of the config to provide before running the model, with playground secrets set <VAR> (or export <VAR>=…):"
    while IFS='|' read -r key reason
    do
      echo "   $(echo "$key" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]/_/g'): $key ($reason)"
    done < $tmp_dir/to_fill
  fi
  log "💡 once it runs, compare it with the customer file: playground connector diff --connector <c> --file $config_file"
fi

# benchmark-load.bash: the load of playground connector benchmark for a source example
for file in README.md docker-compose*.yml keyfile.json stop.sh sql-datagen benchmark-load.bash config-*.json config-*.txt
do
  if [ -f $file ]
  then
    cd $repro_dir > /dev/null
    ln -sf ../../$dir2/$file .
    cd - > /dev/null
  fi
done

for file in .gitignore
do
  if [ -f $file ]
  then
    cd $repro_dir > /dev/null
    cp ../../$dir2/$file .
    cd - > /dev/null
  fi
done

if [ "$producer" != "none" ]
then
  case "${producer}" in
    avro)
      echo "               \"key.converter\": \"org.apache.kafka.connect.storage.StringConverter\"," > $tmp_dir/key_converter
      echo "               \"value.converter\": \"io.confluent.connect.avro.AvroConverter\"," > $tmp_dir/value_converter
      echo "               \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/value_converter
    ;;
    avro-with-key)
      echo "               \"key.converter\": \"io.confluent.connect.avro.AvroConverter\"," > $tmp_dir/key_converter
      echo "               \"key.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/key_converter
      echo "               \"value.converter\": \"io.confluent.connect.avro.AvroConverter\"," > $tmp_dir/value_converter
      echo "               \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/value_converter
    ;;
    json-schema)
      echo "               \"key.converter\": \"org.apache.kafka.connect.storage.StringConverter\"," > $tmp_dir/key_converter
      echo "               \"value.converter\": \"io.confluent.connect.json.JsonSchemaConverter\"," > $tmp_dir/value_converter
      echo "               \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/value_converter
    ;;
    json-schema-with-key)
      echo "               \"key.converter\": \"io.confluent.connect.json.JsonSchemaConverter\"," > $tmp_dir/key_converter
      echo "               \"key.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/key_converter
      echo "               \"value.converter\": \"io.confluent.connect.json.JsonSchemaConverter\"," > $tmp_dir/value_converter
      echo "               \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/value_converter
    ;;
    protobuf)
      echo "               \"key.converter\": \"org.apache.kafka.connect.storage.StringConverter\"," > $tmp_dir/key_converter
      echo "               \"value.converter\": \"io.confluent.connect.protobuf.ProtobufConverter\"," > $tmp_dir/value_converter
      echo "               \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/value_converter
    ;;
    protobuf-with-key)
      echo "               \"key.converter\": \"io.confluent.connect.protobuf.ProtobufConverter\"," > $tmp_dir/key_converter
      echo "               \"key.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/key_converter
      echo "               \"value.converter\": \"io.confluent.connect.protobuf.ProtobufConverter\"," > $tmp_dir/value_converter
      echo "               \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $tmp_dir/value_converter
    ;;
    none)
    ;;
    *)
      logerror "producer name not valid ! Should be one of avro, avro-with-key, json-schema, json-schema-with-key, protobuf or protobuf-with-key"
      exit 1
    ;;
  esac
  original_topic_name=$(grep "\"topics\"" $repro_test_file | cut -d "\"" -f 4 | head -1)
  if [ "$original_topic_name" != "" ]
  then
    tmp=$(echo $original_topic_name | tr '-' '\-')
    sed -e "s|$tmp|$topic_name|g" \
        $repro_test_file > /tmp/tmp

    mv /tmp/tmp $repro_test_file
    # log "✨ Replacing topic $original_topic_name with $topic_name"
  fi

  for((i=1;i<=$nb_producers;i++)); do
    # looks like there is a maximum size for hostname in docker (container init caused: sethostname: invalid argument: unknown)
    producer_hostname=""
    producer_hostname="producer-repro-$description_kebab_case"
    producer_hostname=${producer_hostname:0:21}
    if [ $nb_producers -eq 1 ]
    then
      producer_hostname="${producer_hostname}"
    else
      producer_hostname="${producer_hostname}$i"
    fi

    rm -rf $producer_hostname
    mkdir -p $repro_dir/$producer_hostname/
    cp -Ra ${test_file_directory}/../../other/schema-format-$producer/producer/* $repro_dir/$producer_hostname/

    ####
    #### schema_file_key
    if [[ -n "$schema_file_key" ]]
    then
      log "✨ Copy and paste the schema you want to use for the key, save and close the file to continue"
      playground open --file "$tmp_dir/key_schema" --wait

      case "${producer}" in
        avro-with-key)
          original_namespace=$(cat $tmp_dir/key_schema | jq -r .namespace)
          if [ "$original_namespace" != "null" ]
          then
            sed -e "s|$original_namespace|com.github.vdesabou|g" \
                $tmp_dir/key_schema  > /tmp/tmp

            mv /tmp/tmp $tmp_dir/key_schema
            log "✨ Replacing namespace $original_namespace with com.github.vdesabou"
          else
            # need to add namespace
            cp $tmp_dir/key_schema /tmp/tmp
            line=2
            { head -n $(($line-1)) /tmp/tmp; echo "    \"namespace\": \"com.github.vdesabou\","; tail -n +$line /tmp/tmp; } > $tmp_dir/key_schema
          fi
          # replace record name with MyKey
          jq '.name = "MyKey"' $tmp_dir/key_schema > /tmp/tmp
          mv /tmp/tmp $tmp_dir/key_schema

          cp $tmp_dir/key_schema $repro_dir/$producer_hostname/src/main/resources/schema/mykey.avsc
        ;;
        json-schema-with-key)
          # replace title name with ID
          jq '.title = "ID"' $tmp_dir/key_schema > /tmp/tmp
          mv /tmp/tmp $tmp_dir/key_schema

          cp $tmp_dir/key_schema $repro_dir/$producer_hostname/src/main/resources/schema/Id.json
        ;;
        protobuf-with-key)
          original_package=$(grep "package " $tmp_dir/key_schema | cut -d " " -f 2 | cut -d ";" -f 1 | head -1)
          if [ "$original_package" != "" ]
          then
            sed -e "s|$original_package|com.github.vdesabou|g" \
                $tmp_dir/key_schema  > /tmp/tmp

            mv /tmp/tmp $tmp_dir/key_schema
            log "✨ Replacing package $original_package with com.github.vdesabou"
          else
            # need to add package
            cp $tmp_dir/key_schema /tmp/tmp
            line=2
            { head -n $(($line-1)) /tmp/tmp; echo "package com.github.vdesabou;"; tail -n +$line /tmp/tmp; } > $tmp_dir/key_schema
          fi

          original_java_outer_classname=$(grep "java_outer_classname" $tmp_dir/key_schema | cut -d "\"" -f 2 | cut -d "\"" -f 1 | head -1)
          if [ "$original_java_outer_classname" != "" ]
          then
            sed -e "s|$original_java_outer_classname|IdImpl|g" \
                $tmp_dir/key_schema  > /tmp/tmp

            mv /tmp/tmp $tmp_dir/key_schema
            log "✨ Replacing java_outer_classname $original_java_outer_classname with IdImpl"
          else
            # need to add java_outer_classname
            cp $tmp_dir/key_schema /tmp/tmp
            line=3
            { head -n $(($line-1)) /tmp/tmp; echo "option java_outer_classname = \"IdImpl\";"; tail -n +$line /tmp/tmp; } > $tmp_dir/key_schema
          fi

          cp $tmp_dir/key_schema $repro_dir/$producer_hostname/src/main/resources/schema/Id.proto
        ;;

        none)
        ;;
        *)
          logerror "producer name not valid ! Should be one of avro, avro-with-key, json-schema, json-schema-with-key, protobuf or protobuf-with-key"
          exit 1
        ;;
      esac
    fi

    ####
    #### schema_file_value
    if [[ -n "$schema_file_value" ]]
    then
      log "✨ Copy and paste the schema you want to use for the value, save and close the file to continue"
      playground open --file "$tmp_dir/value_schema" --wait
      
      case "${producer}" in
        avro|avro-with-key)
          original_namespace=$(cat $tmp_dir/value_schema | jq -r .namespace)
          if [ "$original_namespace" != "null" ]
          then
            sed -e "s|$original_namespace|com.github.vdesabou|g" \
                $tmp_dir/value_schema  > /tmp/tmp

            mv /tmp/tmp $tmp_dir/value_schema
            log "✨ Replacing namespace $original_namespace with com.github.vdesabou"
          else
            # need to add namespace
            cp $tmp_dir/value_schema /tmp/tmp
            line=2
            { head -n $(($line-1)) /tmp/tmp; echo "    \"namespace\": \"com.github.vdesabou\","; tail -n +$line /tmp/tmp; } > $tmp_dir/value_schema
          fi
          # replace record name with Customer
          jq '.name = "Customer"' $tmp_dir/value_schema > /tmp/tmp
          mv /tmp/tmp $tmp_dir/value_schema

          cp $tmp_dir/value_schema $repro_dir/$producer_hostname/src/main/resources/schema/customer.avsc
        ;;
        json-schema|json-schema-with-key)
          # replace title name with Customer
          jq '.title = "Customer"' $tmp_dir/value_schema > /tmp/tmp
          mv /tmp/tmp $tmp_dir/value_schema

          cp $tmp_dir/value_schema $repro_dir/$producer_hostname/src/main/resources/schema/Customer.json
        ;;
        protobuf|protobuf-with-key)
          original_package=$(grep "package " $tmp_dir/value_schema | cut -d " " -f 2 | cut -d ";" -f 1 | head -1)
          if [ "$original_package" != "" ]
          then
            sed -e "s|$original_package|com.github.vdesabou|g" \
                $tmp_dir/value_schema  > /tmp/tmp

            mv /tmp/tmp $tmp_dir/value_schema
            log "✨ Replacing package $original_package with com.github.vdesabou"
          else
            # need to add package
            cp $tmp_dir/value_schema /tmp/tmp
            line=2
            { head -n $(($line-1)) /tmp/tmp; echo "package com.github.vdesabou;"; tail -n +$line /tmp/tmp; } > $tmp_dir/value_schema
          fi

          original_java_outer_classname=$(grep "java_outer_classname" $tmp_dir/value_schema | cut -d "\"" -f 2 | cut -d "\"" -f 1 | head -1)
          if [ "$original_java_outer_classname" != "" ]
          then
            sed -e "s|$original_java_outer_classname|CustomerImpl|g" \
                $tmp_dir/value_schema  > /tmp/tmp

            mv /tmp/tmp $tmp_dir/value_schema
            log "✨ Replacing java_outer_classname $original_java_outer_classname with CustomerImpl"
          else
            # need to add java_outer_classname
            cp $tmp_dir/value_schema /tmp/tmp
            line=3
            { head -n $(($line-1)) /tmp/tmp; echo "option java_outer_classname = \"CustomerImpl\";"; tail -n +$line /tmp/tmp; } > $tmp_dir/value_schema
          fi

          cp $tmp_dir/value_schema $repro_dir/$producer_hostname/src/main/resources/schema/Customer.proto
        ;;

        none)
        ;;
        *)
          logerror "producer name not valid ! Should be one of avro, avro-with-key, json-schema, json-schema-with-key, protobuf or protobuf-with-key"
          exit 1
        ;;
      esac
    fi

    # update docker compose with producer container
    if [[ "$dir1" = *connect ]]
    then
        cat << EOF >> $tmp_dir/producer

  $producer_hostname:
    build:
      context: ../../$output_folder/$final_dir/$producer_hostname/
    hostname: producer
    container_name: $producer_hostname
    environment:
      KAFKA_BOOTSTRAP_SERVERS: broker:9092
      TOPIC: "$topic_name"
      REPLICATION_FACTOR: 1
      NUMBER_OF_PARTITIONS: 1
      NB_MESSAGES: 10 # -1 for MAX_VALUE
      MESSAGE_BACKOFF: 100 # Frequency of message injection
      KAFKA_ACKS: "all" # default: "1"
      KAFKA_REQUEST_TIMEOUT_MS: 20000
      KAFKA_RETRY_BACKOFF_MS: 500
      KAFKA_CLIENT_ID: "my-java-$producer_hostname"
      KAFKA_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
      JAVA_OPTS: \${GRAFANA_AGENT_PRODUCER}
    volumes:
      - ../../environment/plaintext/jmx-exporter:/usr/share/jmx_exporter/
      - ../../$output_folder/$final_dir/$producer_hostname/target/producer-1.0.0-jar-with-dependencies.jar:/producer-1.0.0-jar-with-dependencies.jar


EOF
    fi

    if [[ "$dir1" = *ccloud ]]
    then
        cat << EOF >> $tmp_dir/producer

  $producer_hostname:
    build:
      context: ../../$output_folder/$final_dir/$producer_hostname/
    hostname: producer
    container_name: $producer_hostname
    environment:
      KAFKA_BOOTSTRAP_SERVERS: \$BOOTSTRAP_SERVERS
      KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM: "https"
      KAFKA_SASL_MECHANISM: "PLAIN"
      KAFKA_SASL_JAAS_CONFIG: \$SASL_JAAS_CONFIG
      KAFKA_SECURITY_PROTOCOL: "SASL_SSL"
      TOPIC: "$topic_name"
      REPLICATION_FACTOR: 3
      NUMBER_OF_PARTITIONS: 1
      NB_MESSAGES: 10 # -1 for MAX_VALUE
      MESSAGE_BACKOFF: 100 # Frequency of message injection
      KAFKA_ACKS: "all" # default: "1"
      KAFKA_REQUEST_TIMEOUT_MS: 20000
      KAFKA_RETRY_BACKOFF_MS: 500
      KAFKA_CLIENT_ID: "my-java-$producer_hostname"
      KAFKA_SCHEMA_REGISTRY_URL: \$SCHEMA_REGISTRY_URL
      KAFKA_BASIC_AUTH_CREDENTIALS_SOURCE: \$BASIC_AUTH_CREDENTIALS_SOURCE
      KAFKA_SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO: \$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO
      JAVA_OPTS: \${GRAFANA_AGENT_PRODUCER}
      EXTRA_ARGS: 
    volumes:
      - ../../environment/plaintext/jmx-exporter:/usr/share/jmx_exporter/
      - ../../$output_folder/$final_dir/$producer_hostname/target/producer-1.0.0-jar-with-dependencies.jar:/producer-1.0.0-jar-with-dependencies.jar

EOF
    fi
  done

  if [ "${docker_compose_file}" != "" ]
  then
    cp $docker_compose_test_file $tmp_dir/tmp_file
    line=$(grep -n 'services:' $docker_compose_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/producer; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $docker_compose_test_file

  else 
    logwarn "As docker-compose override file could not be determined, you will need to add this manually:"
    cat $tmp_dir/producer
  fi

  for((i=1;i<=$nb_producers;i++)); do
    log "✨ Adding Java $producer producer in $repro_dir/$producer_hostname"
    producer_hostname=""
    producer_hostname="producer-repro-$description_kebab_case"
    producer_hostname=${producer_hostname:0:21} 
    if [ $nb_producers -eq 1 ]
    then
      producer_hostname="${producer_hostname}"
    else
      producer_hostname="${producer_hostname}$i"
    fi

    list="$list $producer_hostname"

  done
    cat << EOF > $tmp_dir/build_producer
for component in $list
do
    set +e
    log "🏗 Building jar for \${component}"
    build_java_component_with_retry "\${component}" docker run -i --rm -e KAFKA_CLIENT_TAG=\$KAFKA_CLIENT_TAG -e TAG=\$TAG_BASE -v "\${DIR}/\${component}":/usr/src/mymaven -v "\$HOME/.m2":/root/.m2 -v "\$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "\${DIR}/\${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=\$TAG -Dkafka.client.tag=\$KAFKA_CLIENT_TAG package
    set -e
done

EOF
  # log "✨ Adding command to build jar for $producer_hostname to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n 'playground start-environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/build_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file

  kafka_cli_producer_error=0
  kafka_cli_producer_eof=0
  line_kafka_cli_producer=$(grep -En "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $repro_test_file | cut -d ":" -f 1 | tail -n1)
  if [ $? != 0 ] || [ "$line_kafka_cli_producer" == "" ]
  then
      logwarn "Could not find kafka cli producer!"
      kafka_cli_producer_error=1
  fi
  set +e
  grep -E "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $repro_test_file | grep EOF > /dev/null
  if [ $? = 0 ]
  then
      kafka_cli_producer_eof=1

      sed -n "$line_kafka_cli_producer,$(($line_kafka_cli_producer + 10))p" $repro_test_file > /tmp/tmp
      tmp=$(grep -n "^EOF" /tmp/tmp | cut -d ":" -f 1 | tail -n1)
      if [ $tmp == "" ]
      then
        logwarn "Could not determine EOF for kafka cli producer!"
        kafka_cli_producer_error=1
      fi
      line_kafka_cli_producer_end=$(($line_kafka_cli_producer + $tmp))
  fi
  set -e
  if [ $kafka_cli_producer_error = 1 ]
  then
    cat << EOF >> $tmp_dir/java_producer
# 🚨🚨🚨 FIXTHIS: move it to the correct place 🚨🚨🚨
EOF
  fi

  for((i=1;i<=$nb_producers;i++)); do
    producer_hostname=""
    producer_hostname="producer-repro-$description_kebab_case"
    producer_hostname=${producer_hostname:0:21} 
    if [ $nb_producers -eq 1 ]
    then
      producer_hostname="${producer_hostname}"
    else
      producer_hostname="${producer_hostname}$i"
    fi

    producer_log_topic="$topic_name"
    producer_topic_override=""
    producer_detach_flag=""
    producer_version_label=""

    if [ $nb_producers -gt 1 ]
    then
      producer_version_label=" v$i"
    fi

    if [[ "$description_kebab_case" == *perf* ]]
    then
      producer_log_topic="${topic_name}${i}"
      producer_topic_override="-e TOPIC=${producer_log_topic}"
      producer_detach_flag="-d"
      producer_version_label=" v$i"
    fi

    cat << EOF >> $tmp_dir/java_producer
log "✨ Run the $producer java producer${producer_version_label} which produces to topic ${producer_log_topic}"
docker exec ${producer_topic_override} ${producer_detach_flag} $producer_hostname bash -c "java \${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

EOF
  done
  if [ $kafka_cli_producer_error = 1 ]
  then
    cat << EOF >> $tmp_dir/java_producer
# 🚨🚨🚨 FIXTHIS: move it to the correct place 🚨🚨🚨
EOF
  fi
  # log "✨ Adding command to run producer to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file

  if [ $kafka_cli_producer_error == 1 ]
  then
      { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/java_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file
  else
    if [ $kafka_cli_producer_eof == 0 ]
    then
      line_kafka_cli_producer_end=$(($line_kafka_cli_producer + 1))
    fi
    { head -n $(($line_kafka_cli_producer - 2)) $tmp_dir/tmp_file; cat $tmp_dir/java_producer; tail -n +$line_kafka_cli_producer_end $tmp_dir/tmp_file; } > $repro_test_file
  fi

  # deal with converters

  sink_key_converter=$(grep "\"key.converter\"" $repro_test_file | cut -d '"' -f 4)
  if [ "$sink_key_converter" == "" ]
  then
    log "💱 Sink connector is using default key.converter, i.e org.apache.kafka.connect.storage.StringConverter"
  else
    if [ "$sink_key_converter" == "org.apache.kafka.connect.json.JsonConverter" ]
    then
      # check schemas.enable
      sink_key_json_converter_schemas_enable=$(grep "\"key.converter.schemas.enable\"" $repro_test_file | cut -d '"' -f 4)
      if [ "$sink_key_json_converter_schemas_enable" == "" ]
      then
        log "💱 Sink connector is using key.converter $sink_key_converter with schemas.enable=true"
      else
        log "💱 Sink connector is using key.converter $sink_key_converter with schemas.enable=$sink_key_json_converter_schemas_enable"
      fi
    else
      log "💱 Sink connector is using key.converter $sink_key_converter"
    fi
  fi

  sink_value_converter=$(grep "\"value.converter\"" $repro_test_file | cut -d '"' -f 4)
  if [ "$sink_value_converter" == "" ]
  then
    log "💱 Sink connector is using default value.converter, i.e io.confluent.connect.avro.AvroConverter"
  else
    if [ "$sink_value_converter" == "org.apache.kafka.connect.json.JsonConverter" ]
    then
      # check schemas.enable
      sink_value_json_converter_schemas_enable=$(grep "\"value.converter.schemas.enable\"" $repro_test_file | cut -d '"' -f 4)
      if [ "$sink_value_json_converter_schemas_enable" == "" ]
      then
        log "💱 Sink connector is using value.converter $sink_value_converter with schemas.enable=true"
      else
        log "💱 Sink connector is using value.converter $sink_value_converter with schemas.enable=$sink_value_json_converter_schemas_enable"
      fi
    else
      log "💱 Sink connector is using value.converter $sink_value_converter"
    fi
  fi

  if [ "$sink_value_converter" == "" ]
  then
    line=$(grep -n 'connector.class' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $repro_test_file; cat $tmp_dir/value_converter; tail -n +$(($line+1)) $repro_test_file; } > $tmp_dir/tmp_file2
    cp $tmp_dir/tmp_file2 $repro_test_file
  else
    # remove existing value.converter
    grep -vwE "\"value.converter" $repro_test_file > $tmp_dir/tmp_file2
    cp $tmp_dir/tmp_file2 $repro_test_file

    line=$(grep -n 'connector.class' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $repro_test_file; cat $tmp_dir/value_converter; tail -n +$(($line+1)) $repro_test_file; } > $tmp_dir/tmp_file2
    cp $tmp_dir/tmp_file2 $repro_test_file
  fi
  log "🔮 Changing Sink connector value.converter to use same as producer:"
  cat $tmp_dir/value_converter

  if [ "$sink_key_converter" == "" ]
  then
    line=$(grep -n 'connector.class' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $repro_test_file; cat $tmp_dir/key_converter; tail -n +$(($line+1)) $repro_test_file; } > $tmp_dir/tmp_file2
    cp $tmp_dir/tmp_file2 $repro_test_file
  else
    # remove existing key.converter
    grep -vwE "\"key.converter" $repro_test_file > $tmp_dir/tmp_file2
    cp $tmp_dir/tmp_file2 $repro_test_file

    line=$(grep -n 'connector.class' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $repro_test_file; cat $tmp_dir/key_converter; tail -n +$(($line+1)) $repro_test_file; } > $tmp_dir/tmp_file2
    cp $tmp_dir/tmp_file2 $repro_test_file
  fi
  log "🔮 Changing Sink connector key.converter to use same as producer:"
  cat $tmp_dir/key_converter
fi


if [[ -n "$add_custom_smt" ]]
then
  custom_smt_name=""
  custom_smt_name="MyCustomSMT-$description_kebab_case"
  custom_smt_name=${custom_smt_name:0:18}
  mkdir -p $repro_dir/$custom_smt_name/
  cp -Ra ../../other/custom-smt/MyCustomSMT/* $repro_dir/$custom_smt_name/
    cat << EOF > $tmp_dir/build_custom_smt
for component in $custom_smt_name
do
    set +e
    log "🏗 Building jar for \${component}"
    build_java_component_with_retry "\${component}" docker run -i --rm -e KAFKA_CLIENT_TAG=\$KAFKA_CLIENT_TAG -e TAG=\$TAG_BASE -v "\${DIR}/\${component}":/usr/src/mymaven -v "\$HOME/.m2":/root/.m2 -v "\$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "\${DIR}/\${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-17 mvn -s /tmp/settings.xml -Dkafka.tag=\$TAG -Dkafka.client.tag=\$KAFKA_CLIENT_TAG package
    set -e
done

EOF

  # log "✨ Adding command to build jar for $custom_smt_name to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n 'playground start-environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/build_custom_smt; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file

  get_connector_paths
  if [ "$connector_paths" == "" ]
  then
      logwarn "❌ skipping as it is not an example with connector, but --custom-smt is set"
      exit 1
  else
    ###
    #  Loop on all connectors in CONNECT_PLUGIN_PATH and install custom SMT jar in lib folder
    ###
    for connector_path in ${connector_paths//,/ }
    do
      echo "log \"📂 Copying custom jar to connector folder $connector_path/lib/\"" >> $tmp_dir/build_custom_docker_cp_smt
      echo "playground container cp --source $repro_dir/$custom_smt_name/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar --destination connect:$connector_path/lib/" >> $tmp_dir/build_custom_docker_cp_smt
    done
    echo "log \"♻️ Restart connect worker to load\"" >> $tmp_dir/build_custom_docker_cp_smt
    echo "playground container restart --container connect" >> $tmp_dir/build_custom_docker_cp_smt
  fi

  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n 'playground start-environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line+2)) $tmp_dir/tmp_file; cat $tmp_dir/build_custom_docker_cp_smt; tail -n +$(($line+2)) $tmp_dir/tmp_file; } > $repro_test_file

  existing_transforms=$(grep "\"transforms\"" $repro_test_file | cut -d '"' -f 4)
  if [ "$existing_transforms" == "" ]
  then
    echo "              \"transforms\": \"MyCustomSMT\"," >> $tmp_dir/build_custom_smt_json_config
    echo "              \"transforms.MyCustomSMT.type\": \"com.github.vdesabou.kafka.connect.transforms.MyCustomSMT\"," >> $tmp_dir/build_custom_smt_json_config

    cp $repro_test_file $tmp_dir/tmp_file
    line=$(grep -n 'connector.class' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/build_custom_smt_json_config; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $repro_test_file
  else
    log "🤖 Connector is using existing transforms $existing_transforms, the new custom SMT will be added to the list."

    # remove existing transforms
    grep -vwE "\"transforms\"" $repro_test_file > $tmp_dir/tmp_file2
    cp $tmp_dir/tmp_file2 $repro_test_file

    echo "              \"transforms\": \"MyCustomSMT,$existing_transforms\"," >> $tmp_dir/build_custom_smt_json_config
    echo "              \"transforms.MyCustomSMT.type\": \"com.github.vdesabou.kafka.connect.transforms.MyCustomSMT\"," >> $tmp_dir/build_custom_smt_json_config

    cp $repro_test_file $tmp_dir/tmp_file
    line=$(grep -n 'connector.class' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/build_custom_smt_json_config; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $repro_test_file
  fi


fi
####
#### pipeline
remove_connect_cp_version_greater_than_8_blocks () {
  awk '
    /^[[:space:]]*if connect_cp_version_greater_than_8/ {skip=1; next}
    skip && /^[[:space:]]*fi([[:space:]]*#.*)?$/ {skip=0; next}
    !skip {print}
  ' "$1" > $tmp_dir/tmp_file2
  mv $tmp_dir/tmp_file2 "$1"
}

length=${#pipeline_array[@]}
if ((length > 0))
then
  remove_connect_cp_version_greater_than_8_blocks "$repro_test_file"
fi

for sink_file in "${pipeline_array[@]}"; do
  if [[ -n "$sink_file" ]]
  then
    if [[ $sink_file == *"@"* ]]
    then
      sink_file=$(echo "$sink_file" | cut -d "@" -f 2)
    fi
    test_sink_file_directory="$(dirname "${sink_file}")"
    ## 
    # docker-compose part
    # determining the docker-compose file from from test_file
    docker_compose_sink_file=$(grep "start-environment" "$sink_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
    docker_compose_sink_file="${test_sink_file_directory}/${docker_compose_sink_file}"
    cp $docker_compose_test_file /tmp/1.yml
    cp $docker_compose_sink_file /tmp/2.yml
    yq ". *= load(\"/tmp/1.yml\")" /tmp/2.yml > $docker_compose_test_file

    connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
    sink_connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_sink_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
    if [ "$sink_connector_paths" == "" ]
    then
      logerror "cannot find CONNECT_PLUGIN_PATH in  ${docker_compose_sink_file}"
      exit 1
    else
      tmp_new_connector_paths="$connector_paths,$sink_connector_paths"
      new_connector_paths=$(echo "$tmp_new_connector_paths" | sed 's/ //g')
      cp $docker_compose_test_file /tmp/1.yml

      yq -i ".services.connect.environment.CONNECT_PLUGIN_PATH = \"$new_connector_paths\"" /tmp/1.yml
      cp /tmp/1.yml $docker_compose_test_file
    fi

    ## 
    # sh part
    
    line_final_source=$(grep -n 'source ${DIR}/../../scripts/utils.sh' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    line_final_environment=$(grep -n 'playground start-environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
    line_sink_source=$(grep -n 'source ${DIR}/../../scripts/utils.sh' $sink_file | cut -d ":" -f 1 | tail -n1) 
    line_sink_environment=$(grep -n 'playground start-environment' $sink_file | cut -d ":" -f 1 | tail -n1)

    # get converter info
    source_key_converter=$(grep "\"key.converter\"" $repro_test_file | cut -d '"' -f 4)
    if [ "$source_key_converter" == "" ]
    then
      log "💱 Source connector is using default key.converter, i.e org.apache.kafka.connect.storage.StringConverter"
    else
      if [ "$source_key_converter" == "org.apache.kafka.connect.json.JsonConverter" ]
      then
        # check schemas.enable
        source_key_json_converter_schemas_enable=$(grep "\"key.converter.schemas.enable\"" $repro_test_file | cut -d '"' -f 4)
        if [ "$source_key_json_converter_schemas_enable" == "" ]
        then
          log "💱 Source connector is using key.converter $source_key_converter with schemas.enable=true"
        else
          log "💱 Source connector is using key.converter $source_key_converter with schemas.enable=$source_key_json_converter_schemas_enable"
        fi
      else
        log "💱 Source connector is using key.converter $source_key_converter"
      fi
    fi

    source_value_converter=$(grep "\"value.converter\"" $repro_test_file | cut -d '"' -f 4)
    if [ "$source_value_converter" == "" ]
    then
      log "💱 Source connector is using default value.converter, i.e io.confluent.connect.avro.AvroConverter"
    else
      if [ "$source_value_converter" == "org.apache.kafka.connect.json.JsonConverter" ]
      then
        # check schemas.enable
        source_value_json_converter_schemas_enable=$(grep "\"value.converter.schemas.enable\"" $repro_test_file | cut -d '"' -f 4)
        if [ "$source_value_json_converter_schemas_enable" == "" ]
        then
          log "💱 Source connector is using value.converter $source_value_converter with schemas.enable=true"
        else
          log "💱 Source connector is using value.converter $source_value_converter with schemas.enable=$source_value_json_converter_schemas_enable"
        fi
      else
        log "💱 Source connector is using value.converter $source_value_converter"
      fi
    fi

    sink_key_converter=$(grep "\"key.converter\"" $sink_file | cut -d '"' -f 4)
    if [ "$sink_key_converter" == "" ]
    then
      log "💱 Sink connector is using default key.converter, i.e org.apache.kafka.connect.storage.StringConverter"
    else
      if [ "$sink_key_converter" == "org.apache.kafka.connect.json.JsonConverter" ]
      then
        # check schemas.enable
        sink_key_json_converter_schemas_enable=$(grep "\"key.converter.schemas.enable\"" $sink_file | cut -d '"' -f 4)
        if [ "$sink_key_json_converter_schemas_enable" == "" ]
        then
          log "💱 Sink connector is using key.converter $sink_key_converter with schemas.enable=true"
        else
          log "💱 Sink connector is using key.converter $sink_key_converter with schemas.enable=$sink_key_json_converter_schemas_enable"
        fi
      else
        log "💱 Sink connector is using key.converter $sink_key_converter"
      fi
    fi

    sink_value_converter=$(grep "\"value.converter\"" $sink_file | cut -d '"' -f 4)
    if [ "$sink_value_converter" == "" ]
    then
      log "💱 Sink connector is using default value.converter, i.e io.confluent.connect.avro.AvroConverter"
    else
      if [ "$sink_value_converter" == "org.apache.kafka.connect.json.JsonConverter" ]
      then
        # check schemas.enable
        sink_value_json_converter_schemas_enable=$(grep "\"value.converter.schemas.enable\"" $sink_file | cut -d '"' -f 4)
        if [ "$sink_value_json_converter_schemas_enable" == "" ]
        then
          log "💱 Sink connector is using value.converter $sink_value_converter with schemas.enable=true"
        else
          log "💱 Sink connector is using value.converter $sink_value_converter with schemas.enable=$sink_value_json_converter_schemas_enable"
        fi
      else
        log "💱 Sink connector is using value.converter $sink_value_converter"
      fi
    fi

    sed -n "$(($line_sink_source+1)),$(($line_sink_environment-1))p" $sink_file > $tmp_dir/pre_sink
    cp $repro_test_file $tmp_dir/tmp_file

    { head -n $(($line_final_environment-1)) $tmp_dir/tmp_file; cat $tmp_dir/pre_sink; tail -n +$line_final_environment $tmp_dir/tmp_file; } > $repro_test_file
    remove_connect_cp_version_greater_than_8_blocks "$repro_test_file"

    sed -n "$(($line_sink_environment+1)),$ p" $sink_file > $tmp_dir/tmp_file

    # deal with converters
    set +e
    if [ "$source_value_converter" == "" ] && [ "$sink_value_converter" == "" ]
    then
      # do nothing
      :
    else
      grep "\"value.converter" $repro_test_file > $tmp_dir/source_value_converter
      if [ "$sink_value_converter" == "" ]
      then
        line=$(grep -n 'connector.class' $tmp_dir/tmp_file | cut -d ":" -f 1 | tail -n1)
        
        { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/source_value_converter; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $tmp_dir/tmp_file2
        cp $tmp_dir/tmp_file2 $tmp_dir/tmp_file
      else
        # remove existing value.converter
        grep -vwE "\"value.converter" $tmp_dir/tmp_file > $tmp_dir/tmp_file2
        cp $tmp_dir/tmp_file2 $tmp_dir/tmp_file

        line=$(grep -n 'connector.class' $tmp_dir/tmp_file | cut -d ":" -f 1 | tail -n1)
        
        { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/source_value_converter; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $tmp_dir/tmp_file2
        cp $tmp_dir/tmp_file2 $tmp_dir/tmp_file
      fi
      log "🔮 Changing Sink connector value.converter to use same as source:"
      cat $tmp_dir/source_value_converter
    fi
    if [ "$source_key_converter" == "" ] && [ "$sink_key_converter" == "" ]
    then
      # do nothing
      :
    else
      grep "\"key.converter" $repro_test_file > $tmp_dir/source_key_converter
      if [ "$sink_key_converter" == "" ]
      then
        line=$(grep -n 'connector.class' $tmp_dir/tmp_file | cut -d ":" -f 1 | tail -n1)
        
        { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/source_key_converter; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $tmp_dir/tmp_file2
        cp $tmp_dir/tmp_file2 $tmp_dir/tmp_file
      else
        # remove existing key.converter
        grep -vwE "\"key.converter" $tmp_dir/tmp_file > $tmp_dir/tmp_file2
        cp $tmp_dir/tmp_file2 $tmp_dir/tmp_file

        line=$(grep -n 'connector.class' $tmp_dir/tmp_file | cut -d ":" -f 1 | tail -n1)
        
        { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/source_key_converter; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $tmp_dir/tmp_file2
        cp $tmp_dir/tmp_file2 $tmp_dir/tmp_file
      fi
      log "🔮 Changing Sink connector key.converter to use same as source:"
      cat $tmp_dir/source_key_converter
    fi
    set -e
    # need to remove cli which produces and change topic
    # remove the producer of the sink example (and the log line before it): the sink reads what the source produces
    producer_regex="kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer|playground topic produce"
    line_kafka_cli_producer=$(grep -En "$producer_regex" $tmp_dir/tmp_file | cut -d ":" -f 1 | tail -n1)
    set +e
    if [ -z "$line_kafka_cli_producer" ]
    then
      logwarn "Could not find the producer of the sink example, keeping it as is"
      cat $tmp_dir/tmp_file >> $repro_test_file
    else
      line_kafka_cli_producer_end=$(($line_kafka_cli_producer + 1))
      if sed -n "${line_kafka_cli_producer}p" $tmp_dir/tmp_file | grep -q "EOF"
      then
        # heredoc (avro schema...): it ends at the first EOF line after the producer
        tmp=$(tail -n +$(($line_kafka_cli_producer + 1)) $tmp_dir/tmp_file | grep -n "^EOF" | cut -d ":" -f 1 | head -n1)
        if [ "$tmp" == "" ]
        then
          logwarn "Could not determine EOF for the producer of the sink example, keeping it as is"
          line_kafka_cli_producer_end=""
        else
          line_kafka_cli_producer_end=$(($line_kafka_cli_producer + $tmp + 1))
        fi
      fi

      if [ -n "$line_kafka_cli_producer_end" ]
      then
        # head -n 0 (or negative) is an error on macOS
        { if [ $line_kafka_cli_producer -gt 2 ]; then head -n $(($line_kafka_cli_producer - 2)) $tmp_dir/tmp_file; fi; tail -n +$line_kafka_cli_producer_end $tmp_dir/tmp_file; } >  $tmp_dir/tmp_file2
        cat $tmp_dir/tmp_file2 >> $repro_test_file
      else
        cat $tmp_dir/tmp_file >> $repro_test_file
      fi
    fi
    set -e

    awk -F'--topic ' '{print $2}' $repro_test_file > $tmp_dir/tmp
    sed '/^$/d' $tmp_dir/tmp > $tmp_dir/tmp2
    original_topic_name=$(head -1 $tmp_dir/tmp2 | cut -d " " -f1)

    if [ "$original_topic_name" != "" ]
    then
      cp $repro_test_file $tmp_dir/tmp_file
      line=$(grep -n '"topics"' $repro_test_file | cut -d ":" -f 1 | tail -n1)

      # replace the topic of the sink example (adding a second "topics" key would leave the original one in the config)
      sed "${line}s|\"topics\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"topics\": \"$original_topic_name\"|" $tmp_dir/tmp_file > $repro_test_file
    else 
      logwarn "Could not find original topic name! "
      logwarn "You would need to change topics config for sink by yourself."
    fi
  fi
done

cat $repro_test_file > $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file

cat >> $tmp_dir/tmp_file << 'EOF'
# 🧪 end the scenario with its verdict, the check that says the 💥 actual of the header is there (playground repro assert --help):
# playground repro assert --reproduced-if-log "<error of the problem>"
# playground repro assert --reproduced-if-connector-state FAILED --connector <connector>
# playground repro assert --reproduced-if-records-less-than <n> --topic <topic>

#################################################################################################
# 🧠 below is a list of cli commands that are helpful at the end of an example
# 🧠 for full documentation, visit https://kafka-docker-playground.io/#/cli !
#################################################################################################

# 🕵️ to check logs (see https://kafka-docker-playground.io/#/cli?id=%f0%9f%95%b5%ef%b8%8f-logs)
# playground container logs --container connect
# playground container logs --container connect --open
# playground container logs --container connect --errors                # de-duplicated ERRORs + Caused by chain
# playground container logs --container connect --errors --since 10m
# playground container logs --container connect --grep "Caused by" --no-follow

# 😴 use this command if you want to wait for a specific message to appear in logs
# playground container logs --container connect --wait-for-log "<text to search>" --max-wait 600

# 🔌 connector state, config and errors
# playground connector status
# playground connector show-config
# playground connector error-recommendations
# playground connector restart
# playground connector offsets get

# 🐢 use this command if you want to wait for connector consumer lag to be zero
# playground connector show-lag

# 🔢 check data in topics
# playground topic get-number-records --topic <topic>
# playground topic consume --topic <topic> --min-expected-messages 10 --timeout 60
# playground topic display-consumer-offsets

# 🐛 increase log level on the fly
# playground debug log-level set --package <package> --level TRACE

# 💥 simulate network or component failures
# playground debug block-traffic --container connect --destination broker --action start   # then --action stop
# playground container restart --container connect
# playground container kill --container broker

# 🩺 collect diagnostics
# playground debug thread-dump --container connect
# playground debug heap-dump --container connect
# playground debug generate-diagnostics
# playground debug tcp-dump --container connect --port 9092 --duration 60

# 🔄 check if the issue reproduces with another CP or connector version
# playground update-version --tag 8.2.0 --connector-tag <version>
EOF


echo "exit 0" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file

echo "#################################################################################################" >> $tmp_dir/tmp_file
echo "# 🚀 below is a list of snippets that can help you to build your example !" >> $tmp_dir/tmp_file
echo "# 🚀 for full documentation, visit https://kafka-docker-playground.io/#/ !" >> $tmp_dir/tmp_file
echo "#################################################################################################" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file
# if [[ "$base1" == *sink ]]
# then
#   cat $root_folder/scripts/cli/snippets/sink.sh | grep -v "#!/bin/bash" >> $tmp_dir/tmp_file
# fi

mv $tmp_dir/tmp_file $repro_test_file

chmod u+x $repro_test_file
repro_test_filename=$(basename -- "$repro_test_file")

log "🌟 command to run generated example"
echo "playground run -f $repro_dir/$repro_test_filename"

if [[ "$OSTYPE" == "darwin"* ]]
then
    clipboard=$(playground config get clipboard)
    if [ "$clipboard" == "" ]
    then
        playground config set clipboard true
    fi

    if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
    then
        echo "playground run -f $repro_dir/$repro_test_filename"| pbcopy
        log "📋 command to run generated example has been copied to the clipboard (disable with 'playground config clipboard false')"
    fi
fi

# with --no-run, keep the state of the example that is currently running
if [[ ! -n "$no_run" ]]
then
  playground state set run.test_file "$repro_dir/$repro_test_filename"
  playground state set run.connector_type "$(get_connector_type | tr -d '\n')"

  playground open --file "$repro_dir/$repro_test_filename"
fi

# commits of the new model get scanned for secrets and customer data
repro_install_git_hook

increment_cli_metric nb_reproduction_models
log "👷 Number of repro models created so far: $(get_cli_metric nb_reproduction_models)"

nb=$(find $root_folder -name *repro*.sh | wc -l)
set_cli_metric nb_existing_reproduction_models $nb
log "🛠️ Number of repro models available: $(get_cli_metric nb_existing_reproduction_models)"

playground generate-fzf-find-files &
# with --no-run, the state is still the one of the previous example: its docs are not the ones of this model
if [[ ! -n "$no_run" ]]
then
  playground open-docs --only-show-url
fi

if [[ -n "$no_run" ]]
then
  log "🛑 --no-run is set, not running the reproduction model"
  exit 0
fi

if ! repro_confirm_stop_running_environment "Running the new model"
then
  log "🛑 not running it, the model is ready: playground run -f $repro_dir/$repro_test_filename"
  exit 0
fi

if [[ "$repro_test_filename" == *"perf"* ]]
then
  if [[ $test_file == *"connect-debezium-sqlserver"* ]] || [[ $test_file == *"connect-debezium-mysql"* ]] || [[ $test_file == *"connect-debezium-postgresql"* ]] || [[ $test_file == *"connect-debezium-oracle"* ]] || [[ $test_file == *"connect-cdc-oracle"* ]] || [[ $test_file == *"connect-jdbc-sqlserver"* ]] || [[ $test_file == *"connect-jdbc-mysql"* ]] || [[ $test_file == *"connect-jdbc-postgresql"* ]] || [[ $test_file == *"connect-jdbc-oracle"* ]] || [[ $test_file == *"connect-cdc-xstream"* ]]
  then
    log "🌪️ automatically enabling SQL Datagen injection as repro name contains <perf>"
    playground run -f $repro_dir/$repro_test_filename --enable-sql-datagen --force-interactive-repro $flag_list
  else
    if [[ $test_file != *"fully-managed"* ]]
    then
      log "📊 automatically enabling Grafana as repro name contains <perf>"
      playground run -f $repro_dir/$repro_test_filename --enable-jmx-grafana --force-interactive-repro $flag_list
    else 
      playground run -f $repro_dir/$repro_test_filename --force-interactive-repro $flag_list
    fi
  fi
else
  playground run -f $repro_dir/$repro_test_filename --force-interactive-repro $flag_list
fi
