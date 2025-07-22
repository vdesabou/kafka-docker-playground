cur="${args[cur]}"
connect_only="${args[--connect-only]}"

if [[ -n "$connect_only" ]]
then
    get_tag_list_with_fzf "$cur" "1"
else
    get_tag_list_with_fzf "$cur" "0"
fi
