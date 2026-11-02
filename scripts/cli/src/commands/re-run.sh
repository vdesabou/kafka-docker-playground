test_file=$(get_current_test_file) || exit 1

declare -a array_flag_list=()
encoded_array="$(playground state get run.array_flag_list_base64)"
eval "$(echo "$encoded_array" | base64 -d)"
IFS=' ' flag_list="${array_flag_list[*]}"

log "⚡ re-run with playground run -f \"$test_file\" $flag_list"
playground run -f "$test_file" $flag_list --force-interactive-re-run