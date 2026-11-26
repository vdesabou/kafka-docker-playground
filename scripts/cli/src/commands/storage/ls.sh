connector="${args[--connector]}"
url="${args[--url]}"
endpoint="${args[--endpoint]}"
prefix="${args[--prefix]}"
topic="${args[--topic]}"
include="${args[--include]}"
max_objects="${args[--max-objects]}"
json="${args[--json]}"

if [[ -n "$json" ]]
then
    # stdout only gets the json document
    exec 3>&1 1>&2
fi

storage_resolve "$connector" "$url" "$endpoint" "$prefix" || exit 2
storage_show_target

tmp_dir=$(mktemp -d -t pg-storage-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

storage_list "$tmp_dir/listing.json" || exit 2

select_args=(select "--listing=$tmp_dir/listing.json" "--topic=$topic" "--include=$include" "--max-objects=$max_objects" "--label=$storage_label")
if [[ -n "$json" ]]
then
    python3 -I "$root_folder/tools/storage/storage.py" "${select_args[@]}" --report json >&3
else
    python3 -I "$root_folder/tools/storage/storage.py" "${select_args[@]}" --report table
fi
