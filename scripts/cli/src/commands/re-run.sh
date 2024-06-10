test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then
  logerror "❌ file $test_file retrieved from $root_folder/playground.ini does not exist!"
  exit 1
fi

declare -a array_flag_list=()
encoded_array="$(playground state get run.array_flag_list_base64)"
eval "$(echo "$encoded_array" | base64 -d)"
IFS=' ' flag_list="${array_flag_list[*]}"

log "⚡ re-run with playground run -f \"$test_file\" $flag_list"
playground run -f "$test_file" $flag_list --force-interactive-re-run