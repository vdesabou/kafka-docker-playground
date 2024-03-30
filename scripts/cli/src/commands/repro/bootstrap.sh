IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

test_file="${args[--file]}"
description="${args[--description]}"
producer="${args[--producer]}"
nb_producers="${args[--nb-producers]}"
add_custom_smt="${args[--custom-smt]}"

eval "pipeline_array=(${args[--pipeline]})"

schema_file_key="${args[--producer-schema-key]}"
schema_file_value="${args[--producer-schema-value]}"

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
  readonly MENU_LETS_GO="🏭 Create the reproduction model !" #0

  MENU_ENABLE_CUSTOM_SMT="🔧 Add custom SMT $(printf '%*s' $((${MAX_LENGTH}-17-${#MENU_ENABLE_CUSTOM_SMT})) ' ') --custom-smt"

  readonly MENU_DISABLE_CUSTOM_SMT="❌🔧 Disable custom SMT" #3
  readonly MENU_GO_BACK="🔙 Go back"

  last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
  example="$last_two_folders/$filename"

  stop=0
  description=""
  while [ $stop != 1 ]
  do
    length=${#pipeline_array[@]}
    if ((length > 0))
    then
      MENU_PIPELINE="🔖 Add another sink to pipeline $(printf '%*s' $((${MAX_LENGTH}-32-${#MENU_PIPELINE})) ' ') --pipeline"
    else
      MENU_PIPELINE="🔖 Create pipeline with sink $(printf '%*s' $((${MAX_LENGTH}-28-${#MENU_PIPELINE})) ' ') --pipeline"
    fi

    options=("$MENU_LETS_GO" "$MENU_PIPELINE" "$MENU_ENABLE_CUSTOM_SMT" "$MENU_DISABLE_CUSTOM_SMT" "$MENU_GO_BACK")

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

    if [ $connector_example == 0 ]
    then
      for((i=1;i<4;i++)); do
        unset "options[$i]"
      done
    else
      if [[ $test_file == *"sink"* ]]
      then
        unset 'options[1]'
      fi
    fi

    if [ ! -z $CUSTOM_SMT ]
    then
      unset 'options[2]'
    else
      unset 'options[3]'
    fi

    if [ "$description" == "" ]
    then
      maybe_remove_flag "--description"
      set +e
      description=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="💭 " --header="enter a description for this repro model (it cannot be empty !)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
      set -e
      if [ "$description" == "" ]
      then
        continue
      fi
      array_flag_list+=("--description=$description")
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
      stop=1
      playground repro bootstrap
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
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

description_kebab_case="${description// /-}"
description_kebab_case=$(echo "$description_kebab_case" | tr '[:upper:]' '[:lower:]')
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
    echo "version: '3.5'" >> $docker_compose_test_file
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
echo "#" >> $tmp_dir/intro
echo "###############################################" >> $tmp_dir/intro
echo "" >> $tmp_dir/intro

cat $tmp_dir/intro > $tmp_dir/tmp_file
cat $repro_test_file | grep -v "#!/bin/bash" >> $tmp_dir/tmp_file
mv $tmp_dir/tmp_file $repro_test_file

for file in README.md docker-compose*.yml keyfile.json stop.sh .gitignore sql-datagen
do
  if [ -f $file ]
  then
    cd $repro_dir > /dev/null
    ln -sf ../../$dir2/$file .
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



      editor=$(playground config get editor)
      if [ "$editor" != "" ]
      then
        log "✨ Copy and paste the schema you want to use for the key, save and close the file to continue"
        if [ "$editor" = "code" ]
        then
          code --wait $tmp_dir/key_schema
        else
          $editor $tmp_dir/key_schema
        fi
      else
        if [[ $(type code 2>&1) =~ "not found" ]]
        then
          logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
          exit 1
        else
          log "✨ Copy and paste the schema you want to use for the key, save and close the file to continue"
          code --wait $tmp_dir/key_schema
        fi
      fi
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

      editor=$(playground config get editor)
      if [ "$editor" != "" ]
      then
        log "✨ Copy and paste the schema you want to use for the value, save and close the file to continue"
        if [ "$editor" = "code" ]
        then
          code --wait $tmp_dir/value_schema
        else
          $editor $tmp_dir/value_schema
        fi
      else
        if [[ $(type code 2>&1) =~ "not found" ]]
        then
          logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
          exit 1
        else
          log "✨ Copy and paste the schema you want to use for the value, save and close the file to continue"
          code --wait $tmp_dir/value_schema
        fi
      fi

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
    docker run -i --rm -e KAFKA_CLIENT_TAG=\$KAFKA_CLIENT_TAG -e TAG=\$TAG_BASE -v "\${DIR}/\${component}":/usr/src/mymaven -v "\$HOME/.m2":/root/.m2 -v "\$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "\${DIR}/\${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=\$TAG -Dkafka.client.tag=\$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ \$? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

EOF
  # log "✨ Adding command to build jar for $producer_hostname to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n 'playground start-environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/build_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file

  kafka_cli_producer_error=0
  kafka_cli_producer_eof=0
  line_kafka_cli_producer=$(egrep -n "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $repro_test_file | cut -d ":" -f 1 | tail -n1)
  if [ $? != 0 ] || [ "$line_kafka_cli_producer" == "" ]
  then
      logwarn "Could not find kafka cli producer!"
      kafka_cli_producer_error=1
  fi
  set +e
  egrep "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $repro_test_file | grep EOF > /dev/null
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
    get_producer_run_heredoc
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
    docker run -i --rm -e KAFKA_CLIENT_TAG=\$KAFKA_CLIENT_TAG -e TAG=\$TAG_BASE -v "\${DIR}/\${component}":/usr/src/mymaven -v "\$HOME/.m2":/root/.m2 -v "\$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "\${DIR}/\${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=\$TAG -Dkafka.client.tag=\$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ \$? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
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
      echo "docker cp $repro_dir/$custom_smt_name/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar connect:$connector_path/lib/" >> $tmp_dir/build_custom_docker_cp_smt
    done
    echo "log \"♻️ Restart connect worker to load\"" >> $tmp_dir/build_custom_docker_cp_smt
    echo "docker restart connect" >> $tmp_dir/build_custom_docker_cp_smt
    echo "sleep 45" >> $tmp_dir/build_custom_docker_cp_smt
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
    kafka_cli_producer_error=0
    kafka_cli_producer_eof=0
    line_kafka_cli_producer=$(egrep -n "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $tmp_dir/tmp_file | cut -d ":" -f 1 | tail -n1)
    if [ $? != 0 ]
    then
        logwarn "Could not find kafka cli producer!"
        kafka_cli_producer_error=1
    fi
    set +e
    egrep "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $tmp_dir/tmp_file | grep EOF > /dev/null
    if [ $? = 0 ]
    then
        kafka_cli_producer_eof=1

        sed -n "$line_kafka_cli_producer,$(($line_kafka_cli_producer + 10))p" $tmp_dir/tmp_file > /tmp/tmp
        tmp=$(grep -n "^EOF" /tmp/tmp | cut -d ":" -f 1 | tail -n1)
        if [ $tmp == "" ]
        then
          logwarn "Could not determine EOF for kafka cli producer!"
          kafka_cli_producer_error=1
        fi
        line_kafka_cli_producer_end=$(($line_kafka_cli_producer + $tmp))
    fi


    if [ $kafka_cli_producer_error == 0 ]
    then
      if [ $kafka_cli_producer_eof == 0 ]
      then
        line_kafka_cli_producer_end=$(($line_kafka_cli_producer + 1))
      fi
      { head -n $(($line_kafka_cli_producer - 2)) $tmp_dir/tmp_file; tail -n +$line_kafka_cli_producer_end $tmp_dir/tmp_file; } >  $tmp_dir/tmp_file2
      cat  $tmp_dir/tmp_file2 >> $repro_test_file
    fi
    set -e

    awk -F'--topic ' '{print $2}' $repro_test_file > $tmp_dir/tmp
    sed '/^$/d' $tmp_dir/tmp > $tmp_dir/tmp2
    original_topic_name=$(head -1 $tmp_dir/tmp2 | cut -d " " -f1)

    if [ "$original_topic_name" != "" ]
    then
      cp $repro_test_file $tmp_dir/tmp_file
      line=$(grep -n '"topics"' $repro_test_file | cut -d ":" -f 1 | tail -n1)
      
      echo "              \"topics\": \"$original_topic_name\"," > $tmp_dir/topic_line
      { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/topic_line; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $repro_test_file
    else 
      logwarn "Could not find original topic name! "
      logwarn "You would need to change topics config for sink by yourself."
    fi
  fi
done

cat $repro_test_file > $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file

echo "#################################################################################################" >> $tmp_dir/tmp_file
echo "# 🧠 below is a list of cli commands that are helpful at the end of an example" >> $tmp_dir/tmp_file
echo "# 🧠 for full documentation, visit https://kafka-docker-playground.io/#/cli !" >> $tmp_dir/tmp_file
echo "#################################################################################################" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file
echo "# 🕵️ to check logs (see https://kafka-docker-playground.io/#/cli?id=%f0%9f%95%b5%ef%b8%8f-logs)" >> $tmp_dir/tmp_file
echo "# Example: check logs" >> $tmp_dir/tmp_file
echo "# playground container logs --container connect" >> $tmp_dir/tmp_file
echo "# playground container logs --container connect --open" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file
echo "# 😴 use this command if you want to wait for a specific message to appear in logs" >> $tmp_dir/tmp_file
echo "# playground container logs --container connect --wait-for-log \"<text to search>\" --max-wait 600" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file
echo "# 🐢 use this command if you want to wait for connector consumer lag to be zero" >> $tmp_dir/tmp_file
echo "# playground connector show-lag" >> $tmp_dir/tmp_file


echo "exit 0" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file

echo "#################################################################################################" >> $tmp_dir/tmp_file
echo "# 🚀 below is a list of snippets that can help you to build your example !" >> $tmp_dir/tmp_file
echo "# 🚀 for full documentation, visit https://kafka-docker-playground.io/#/ !" >> $tmp_dir/tmp_file
echo "#################################################################################################" >> $tmp_dir/tmp_file
echo "" >> $tmp_dir/tmp_file
if [[ "$base1" == *sink ]]
then
  cat $root_folder/scripts/cli/snippets/sink.sh | grep -v "#!/bin/bash" >> $tmp_dir/tmp_file
fi

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
        log "📋 command to run generated example has been copied to the clipboard (disable with 'playground config set clipboard false')"
    fi
fi

playground state set run.test_file "$repro_dir/$repro_test_filename"
playground state set run.connector_type "$(get_connector_type | tr -d '\n')"

editor=$(playground config get editor)
if [ "$editor" != "" ]
then
  log "📖 Opening ${repro_test_filename} using configured editor $editor"
  $editor $repro_dir/$repro_test_filename
else
    if [[ $(type code 2>&1) =~ "not found" ]]
    then
        logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
        exit 1
    else
        log "📖 Opening ${repro_test_filename} with code (default) - you can change editor by using playground config editor <editor>"
        code $repro_dir/$repro_test_filename
    fi
fi

increment_cli_metric nb_reproduction_models
log "👷 Number of repro models created so far: $(get_cli_metric nb_reproduction_models)"

nb=$(find $root_folder -name *repro*.sh | wc -l)
set_cli_metric nb_existing_reproduction_models $nb
log "🛠️ Number of repro models available: $(get_cli_metric nb_existing_reproduction_models)"

playground generate-fzf-find-files &
playground open-docs --only-show-url
playground run -f $repro_dir/$repro_test_filename --force-interactive-repro $flag_list