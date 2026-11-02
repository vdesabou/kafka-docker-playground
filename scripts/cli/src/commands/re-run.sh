test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then
  logerror "❌ file $test_file retrieved from $root_folder/playground.ini does not exist!"
  exit 1
fi

declare -a array_flag_list=()
encoded_array="$(playground state get run.array_flag_list_base64)"
eval "$(echo "$encoded_array" | base64 -d)"
flag_list_to_args
command_line="playground run -f $(printf '%q' "$test_file")"
if [ ${#flag_args[@]} -gt 0 ]
then
  command_line+="$(printf ' %q' "${flag_args[@]}")"
fi

log "⚡ re-run with $(mask_creds_in_command "$command_line")"
playground run -f "$test_file" "${flag_args[@]}" --force-interactive-re-run