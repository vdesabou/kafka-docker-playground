open="${args[--open]}"

function get_all_schemas() {
  ret=$(get_sr_url_and_security)

  sr_url=$(echo "$ret" | cut -d "@" -f 1)
  sr_security=$(echo "$ret" | cut -d "@" -f 2)

  # Get a list of all subjects in the schema registry
  subjects=$(curl $sr_security -s "${sr_url}/subjects")

  if [[ -n "$open" ]]
  then
    echo "Displaying all subjects 🔰 and versions 💯"
  else
    log "Displaying all subjects 🔰 and versions 💯"
  fi
  for subject in $(echo "${subjects}" | jq -r '.[]'); do
    versions=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions")

    for version in $(echo "${versions}" | jq -r '.[]')
    do
      schema_type=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}"  | jq -r .schemaType)
      case "${schema_type}" in
        JSON|null)
          schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema" | jq .)
        ;;
        PROTOBUF)
          schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/${version}/schema")
        ;;
      esac

      if [[ -n "$open" ]]
      then
        echo "🔰 ${subject} 💯 ${version}"
      else
        log "🔰 ${subject} 💯 ${version}"
      fi
      echo "${schema}"
    done
  done
}

if [[ -n "$open" ]]
then
  filename="/tmp/get-all-schemas-`date '+%Y-%m-%d-%H-%M-%S'`.log"
  log "Opening $filename with editor $editor"
  get_all_schemas > "$filename" 2>&1
  if [ $? -eq 0 ]
  then
    if config_has_key "editor"
    then
      editor=$(config_get "editor")
      log "📖 Opening ${filename} using configured editor $editor"
      $editor $filename
    else
      if [[ $(type code 2>&1) =~ "not found" ]]
      then
        logerror "Could not determine an editor to use as default code is not found - you can change editor by updating config.ini"
        exit 1
      else
        log "📖 Opening ${filename} with code (default) - you can change editor by updating config.ini"
        code $filename
      fi
    fi
  else
    logerror "Failed to get schemas"
  fi
else 
  get_all_schemas
fi