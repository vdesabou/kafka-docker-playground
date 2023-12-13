cur="${args[cur]}"

find $root_folder -type f ! -path '*/\.*' > /tmp/get_any_files_with_fzf
get_any_files_with_fzf "$cur"