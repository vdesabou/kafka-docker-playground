tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"

test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

# determining the docker-compose file from from test_file
docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
test_file_directory="$(dirname "${test_file}")"
docker_compose_file="${test_file_directory}/${docker_compose_file}"

docker_compose_file_available=1
if [ "${docker_compose_file}" != "" ] && [ ! -f "${docker_compose_file}" ]
then
  docker_compose_file_available=0
fi

current_tag=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)

if [ "$current_tag" == "" ]
then
  logerror "❌ Could not retrieve current cp version (--tag or TAG) being used"
  exit 1
fi

declare -a array_flag_list=()
if [[ -n "$tag" ]]
then
  if [[ $tag == *"@"* ]]
  then
    tag=$(echo "$tag" | cut -d "@" -f 2)
  fi
  array_flag_list+=("--tag=$tag")
  export TAG=$tag
fi

if [[ -n "$connector_tag" ]]
then
  if [ "$connector_tag" == " " ]
  then
    get_connector_paths
    if [ "$connector_paths" == "" ]
    then
        logwarn "❌ skipping as it is not an example with connector, but --connector-tag is set"
        exit 1
    else
        connector_tags=""
        for connector_path in ${connector_paths//,/ }
        do
          full_connector_name=$(basename "$connector_path")
          owner=$(echo "$full_connector_name" | cut -d'-' -f1)
          name=$(echo "$full_connector_name" | cut -d'-' -f2-)

          if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
          then
            # happens when plugin is not coming from confluent hub
            # logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
            continue
          fi

          ret=$(choose_connector_tag "$owner/$name")
          connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
          
          if [ -z "$connector_tags" ]; then
            connector_tags="$connector_tag"
          else
            connector_tags="$connector_tags,$connector_tag"
          fi
        done

        connector_tag="$connector_tags"
    fi
  fi

  array_flag_list+=("--connector-tag=$connector_tag")
  export CONNECTOR_TAG="$connector_tag"
fi

if [[ -n "$connector_zip" ]]
then
  if [[ $connector_zip == *"@"* ]]
  then
    connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
  fi
  array_flag_list+=("--connector-zip=$connector_zip")
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
  fi
  array_flag_list+=("--connector-jar=$connector_jar")
  export CONNECTOR_JAR=$connector_jar
fi

IFS=' ' flag_list="${array_flag_list[*]}"
if [ "$flag_list" == "" ]
then
  docs_available=1
  set +e
  playground open-docs --only-show-url > /dev/null 2>&1
  if [ $? -eq 1 ]
  then
    docs_available=0
  fi
  set -e

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

  connector_example=0
  current_versions=""
  get_connector_paths
  if [ "$connector_paths" != "" ]
  then
    connector_tags=""
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

        ## current version
        manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
        if [ -f $manifest_file ]
        then
          current_version=$(cat $manifest_file | jq -r '.version')
          # release_date=$(cat $manifest_file | jq -r '.release_date')

          if [ -z "$current_versions" ]; then
            current_versions="$current_version"
          else
            current_versions="$current_versions,$current_version"
          fi
        else
          change_detected=1
        fi
        connector_example=1
      fi
    done
  fi

  # readonly MENU_LETS_GO="🚀 Run the example !" #0
  readonly MENU_OPEN_FILE="📖 Open the file in text editor"
  set +e
  if [[ $(type -f open 2>&1) =~ "not found" ]]
  then
    MENU_OPEN_DOCS="🌐 Show link to the docs"
  else
    MENU_OPEN_DOCS="🌐 Open the docs in browser"
  fi
  set -e
  readonly MENU_SEPARATOR="--------------------------------------------------" #3
  MENU_TAG="🎯 CP version (current $current_tag) $(printf '%*s' $((${MAX_LENGTH}-29-${#MENU_TAG})) ' ') --tag" #4
  MENU_CONNECTOR_TAG="🔗 Connector version (current $current_versions) $(printf '%*s' $((${MAX_LENGTH}-44-${#MENU_CONNECTOR_TAG})) ' ') --connector-tag"
  MENU_CONNECTOR_ZIP="🤐 Connector zip $(printf '%*s' $((${MAX_LENGTH}-16-${#MENU_CONNECTOR_ZIP})) ' ') --connector-zip"
  MENU_CONNECTOR_JAR="🤎 Connector jar $(printf '%*s' $((${MAX_LENGTH}-16-${#MENU_CONNECTOR_JAR})) ' ') --connector-jar"

  readonly MENU_GO_BACK="🔙 Go back"

  last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
  example="$last_two_folders/$filename"

  stop=0
  change_detected=0
  while [ $stop != 1 ]
  do
    if [ $change_detected -eq 0 ]
    then
      MENU_LETS_GO="❌ No version change detected !" #0
    else
      MENU_LETS_GO="🚀 Run the example !" #0
    fi
    options=("$MENU_LETS_GO" "$MENU_OPEN_FILE" "$MENU_OPEN_DOCS" "$MENU_SEPARATOR" "$MENU_TAG" "$MENU_CONNECTOR_TAG" "$MENU_CONNECTOR_ZIP" "$MENU_CONNECTOR_JAR" "$MENU_GO_BACK")

    if [[ $test_file == *"ccloud"* ]] || [ "$PLAYGROUND_ENVIRONMENT" == "ccloud" ]
    then
      if [[ $test_file == *"fully-managed"* ]]
      then
        unset 'options[4]'
        unset 'options[5]'
        unset 'options[6]'
        unset 'options[7]'
      fi
    fi

    if [ $connector_example == 0 ] || [ $docker_compose_file_available == 0 ]
    then
      unset 'options[5]'
      unset 'options[6]'
      unset 'options[7]'
    fi

    if [ $docs_available == 0 ]
    then
      unset 'options[2]'
    fi

    oldifs=$IFS
    IFS=$'\n' flag_string="${array_flag_list[*]}"
    IFS=$oldifs

    preview="\n🚀 number of examples ran so far: $(get_cli_metric nb_runs)\n\n⛳ flag list:\n$flag_string\n"
    res=$(printf '%s\n' "${options[@]}" | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select option(s) for $example (use tab to select more than one)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --preview "echo -e \"$preview\"")

    if [[ $res == *"$MENU_LETS_GO"* ]]
    then
      stop=1
    fi

    if [[ $res == *"$MENU_OPEN_FILE"* ]]
    then
      editor=$(playground config get editor)
      if [ "$editor" != "" ]
      then
        log "📖 Opening ${test_file} using configured editor $editor"
        $editor ${test_file}
      else
          if [[ $(type code 2>&1) =~ "not found" ]]
          then
              logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
              exit 1
          else
              log "📖 Opening ${test_file} with code (default) - you can change editor by using playground config editor <editor>"
              code ${test_file}
          fi
      fi
    fi

    if [[ $res == *"$MENU_OPEN_DOCS"* ]]
    then
      if [[ $(type -f open 2>&1) =~ "not found" ]]
      then
        playground open-docs --only-show-url
      else
        playground open-docs
      fi
    fi

    if [[ $res == *"$MENU_GO_BACK"* ]]
    then
      stop=1
      playground update-versions
    fi

    if [[ $res == *"$MENU_TAG"* ]]
    then
      tag=$(playground get-tag-list)
      if [[ $tag == *"@"* ]]
      then
        tag=$(echo "$tag" | cut -d "@" -f 2)
      fi

      if [ "$current_tag" != "$tag" ]
      then
        change_detected=1
        maybe_remove_flag "--tag"
        array_flag_list+=("--tag=$tag")
        export TAG=$tag
      fi
    fi

    if [[ $res == *"$MENU_CONNECTOR_TAG"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-tag"
      connector_tags=""
      for connector_path in ${connector_paths//,/ }
      do
        full_connector_name=$(basename "$connector_path")
        owner=$(echo "$full_connector_name" | cut -d'-' -f1)
        name=$(echo "$full_connector_name" | cut -d'-' -f2-)

        if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
        then
          # happens when plugin is not coming from confluent hub
          continue
        fi

        ## current version
        manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
        if [ -f $manifest_file ]
        then
          current_version=$(cat $manifest_file | jq -r '.version')
          # release_date=$(cat $manifest_file | jq -r '.release_date')
        else
          change_detected=1
        fi

        ret=$(choose_connector_tag "$owner/$name")
        connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
        
        if [ "$current_version" != "$connector_tag" ]
        then
          change_detected=1
        fi

        if [ -z "$connector_tags" ]; then
          connector_tags="$connector_tag"
        else
          connector_tags="$connector_tags,$connector_tag"
        fi
      done

      connector_tag="$connector_tags"
      array_flag_list+=("--connector-tag=$connector_tag")
      export CONNECTOR_TAG="$connector_tag"
    fi

    if [[ $res == *"$MENU_CONNECTOR_ZIP"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-tag"
      maybe_remove_flag "--connector-jar"
      connector_zip=$(playground get-zip-or-jar-with-fzf --type zip)
      if [[ $connector_zip == *"@"* ]]
      then
        connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
      fi
      change_detected=1
      array_flag_list+=("--connector-zip=$connector_zip")
      export CONNECTOR_ZIP=$connector_zip
    fi

    if [[ $res == *"$MENU_CONNECTOR_JAR"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-jar"
      connector_jar=$(playground get-zip-or-jar-with-fzf --type jar)
      if [[ $connector_jar == *"@"* ]]
      then
        connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
      fi
      change_detected=1
      array_flag_list+=("--connector-jar=$connector_jar")
      export CONNECTOR_JAR=$connector_jar
    fi
  done # end while loop stop
fi

tag_changed=0
IFS=' ' flag_list="${array_flag_list[*]}"
if [[ -n "$tag" ]]
then
  current_tag=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)

  if [ "$current_tag" == "" ]
  then
    logerror "❌ Could not retrieve current cp version (--tag or TAG) being used"
    exit 1
  fi
  
  if [ "$current_tag" == "$tag" ]
  then
    logwarn "--tag=$tag is same as current tag, ignoring..."
    array_flag_list=("${array_flag_list[@]/"--tag"}")
  else
    tag_changed=1
  fi
fi

if [ $docker_compose_file_available == 1 ]
then
  export DOCKER_COMPOSE_FILE_UPDATE_VERSION="$docker_compose_file"
fi

IFS=' ' flag_list="${array_flag_list[*]}"
if [ "$flag_list" != "" ]
then
  log "✨ Loading new version(s) based on flags ⛳ $flag_list"
else
  log "✨ Loading new version(s) without any flags ⛳"
fi

if [ $tag_changed -eq 1 ]
then
    log "💣 Detected confluent version change, restarting containers"
    playground container recreate --ignore-current-versions
else
    # in case there is a change in docker-compose...
    playground container recreate
fi

if [[ -n "$connector_tag" ]] || [[ -n "$connector_zip" ]] || [[ -n "$connector_jar" ]]
then
    if [ $tag_changed -eq 0 ]
    then
        log "🧩 a connector flag is set: restarting connect container to make sure new version(s) are used"
        playground container restart --container connect
    fi
    sleep 5

    wait_container_ready

    sleep 10

    playground connector versions
else
    sleep 4

    wait_container_ready
fi