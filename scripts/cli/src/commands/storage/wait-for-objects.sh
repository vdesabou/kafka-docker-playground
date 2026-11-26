connector="${args[--connector]}"
url="${args[--url]}"
endpoint="${args[--endpoint]}"
prefix="${args[--prefix]}"
topic="${args[--topic]}"
include="${args[--include]}"
min_expected_objects="${args[--min-expected-objects]}"
max_wait="${args[--max-wait]}"
interval="${args[--interval]}"

storage_resolve "$connector" "$url" "$endpoint" "$prefix" || exit 2

tmp_dir=$(mktemp -d -t pg-storage-XXXXXXXXXX)
trap 'storage_remove_tmp_dir "$tmp_dir"' EXIT

what="${storage_label}${topic:+ (topic $topic)}${include:+ (matching $include)}"
log "⏳ Waiting up to $max_wait seconds for at least $min_expected_objects object(s) in $what"
start_time=$SECONDS
last_count=""
nb_failures=0
while true
do
    if storage_list "$tmp_dir/listing.json" 2> "$tmp_dir/list.err"
    then
        nb_failures=0
        count=$(python3 -I "$root_folder/tools/storage/storage.py" select "--listing=$tmp_dir/listing.json" "--topic=$topic" "--include=$include" --report count)
    else
        nb_failures=$((nb_failures + 1))
        if [ $nb_failures -ge 3 ]
        then
            cat "$tmp_dir/list.err" >&2
            exit 1
        fi
        count=0
    fi
    elapsed=$((SECONDS - start_time))
    if [ "$count" -ge "$min_expected_objects" ]
    then
        log "✅ $count object(s) in $what (expected at least $min_expected_objects) after $elapsed seconds"
        break
    fi
    if [ "$count" != "$last_count" ]
    then
        log "⌛ $count object(s) (expected at least $min_expected_objects)"
        last_count="$count"
    fi
    if [ $elapsed -ge $max_wait ]
    then
        logerror "❌ $count object(s) in $what after $max_wait seconds, expected at least $min_expected_objects"
        exit 1
    fi
    sleep $interval
done
