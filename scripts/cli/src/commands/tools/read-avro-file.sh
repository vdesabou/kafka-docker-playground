file="${args[--file]}"

if [[ $file == *"@"* ]]
then
  file=$(echo "$file" | cut -d "@" -f 2)
fi

# a file under /tmp is only reachable by the engine through its resolved path on macOS
file=$(host_path "$file")

filename=$(basename $file)

log "🔖 ${filename}.avro metadata"
docker run --quiet --rm -v ${file}:/tmp/${filename} vdesabou/avro-tools getmeta /tmp/${filename}

log "🔖 ${filename}.avro schema"
docker run --quiet --rm -v ${file}:/tmp/${filename} vdesabou/avro-tools getschema /tmp/${filename}

log "🔖 ${filename}.avro content"
docker run --quiet --rm -v ${file}:/tmp/${filename} vdesabou/avro-tools tojson /tmp/${filename}
