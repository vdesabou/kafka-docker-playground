connector="${args[--connector]}"
url="${args[--url]}"
endpoint="${args[--endpoint]}"
prefix="${args[--prefix]}"
topic="${args[--topic]}"
include="${args[--include]}"
max_objects="${args[--max-objects]}"
newest="${args[--newest]}"
records="${args[--records]}"
summary="${args[--summary]}"
json="${args[--json]}"

if [[ -n "$json" || -n "$records" ]]
then
    # stdout only gets the json document / the json lines
    exec 3>&1 1>&2
fi

storage_resolve "$connector" "$url" "$endpoint" "$prefix" || exit 2
storage_show_target

tmp_dir=$(mktemp -d -t pg-storage-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
mkdir -p "$tmp_dir/objects"

storage_list "$tmp_dir/listing.json" || exit 2

select_args=(select "--listing=$tmp_dir/listing.json" "--topic=$topic" "--include=$include" "--max-objects=$max_objects" "--selected=$tmp_dir/selected.txt" "--report=count")
[[ -n "$newest" ]] && select_args+=(--newest)
matched=$(python3 -I "$root_folder/tools/storage/storage.py" "${select_args[@]}") || exit 2
selected=$(grep -c . "$tmp_dir/selected.txt")
if [[ "$selected" -eq 0 ]]
then
    logwarn "🫙 no object${topic:+ for topic $topic}${include:+ matching $include} under $storage_label"
    [[ -n "$json" ]] && echo '{"objects": [], "partitions": []}' >&3
    exit 0
fi
if [[ "$matched" -gt "$selected" ]]
then
    logwarn "📄 reading $selected of $matched objects (--max-objects $max_objects${newest:+, the newest})"
else
    log "📄 reading $selected object(s)"
fi

if ! STORAGE_RCLONE_VOLUME="$tmp_dir" storage_rclone copy --files-from-raw /work/selected.txt --no-traverse "$(storage_remote_path)" /work/objects 2> "$tmp_dir/copy.log"
then
    logerror "❌ could not download the objects:"
    grep -v '^\s*$' "$tmp_dir/copy.log" | tail -5
    exit 2
fi

# avro and parquet objects to json lines, one container for all the objects of a format
if grep -q -i '\.avro$' "$tmp_dir/selected.txt"
then
    docker run --quiet --rm -v "$(host_path "$tmp_dir"):/work" --entrypoint bash vdesabou/avro-tools -c \
        'find /work/objects -type f -name "*.avro" | while read -r f; do java -jar /opt/avro-tools.jar tojson "$f" > "$f.jsonl" 2> "$f.err" || { echo "$f: $(tail -1 "$f.err")" >&2; rm -f "$f.jsonl"; }; done' 2>&1 | sed "s#/work/objects/##" >&2
fi
if grep -q -i '\.parquet$' "$tmp_dir/selected.txt"
then
    docker run --quiet --rm --platform linux/amd64 -v "$(host_path "$tmp_dir"):/work" --entrypoint sh nathanhowell/parquet-tools -c \
        'find /work/objects -type f -name "*.parquet" | while read -r f; do java -jar /parquet-tools.jar cat --json "$f" > "$f.jsonl" 2> "$f.err" || { echo "$f: $(tail -1 "$f.err")" >&2; rm -f "$f.jsonl"; }; done' 2>&1 | sed "s#/work/objects/##" >&2
fi

output="objects"
[[ -n "$summary" ]] && output="summary"
[[ -n "$records" ]] && output="records"
[[ -n "$json" ]] && output="json"
decode_args=(decode "--dir=$tmp_dir/objects" "--selected=$tmp_dir/selected.txt" "--output=$output")
if [[ -n "$json" || -n "$records" ]]
then
    python3 -I "$root_folder/tools/storage/storage.py" "${decode_args[@]}" >&3
else
    python3 -I "$root_folder/tools/storage/storage.py" "${decode_args[@]}"
fi
