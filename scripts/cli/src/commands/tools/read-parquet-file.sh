file="${args[--file]}"

if [[ $file == *"@"* ]]
then
  file=$(echo "$file" | cut -d "@" -f 2)
fi

filename=$(basename $file)

log "🔖 ${filename}.parquet metadata"
docker run --quiet --rm -v ${file}:/tmp/${filename} nathanhowell/parquet-tools meta /tmp/${filename}

log "🔖 ${filename}.parquet schema"
docker run --quiet --rm -v ${file}:/tmp/${filename} nathanhowell/parquet-tools schema /tmp/${filename}

log "🔖 ${filename}.parquet content"
docker run --quiet --rm -v ${file}:/tmp/${filename} nathanhowell/parquet-tools cat /tmp/${filename}
