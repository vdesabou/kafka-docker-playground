cur="${args[cur]}"

file=$(get_example_file_from_completion_words "${other_args[@]}")
res=$(get_client_version_with_fzf "$cur" "$file")
if [ -n "$res" ]
then
  echo "$cur@$res"
fi
