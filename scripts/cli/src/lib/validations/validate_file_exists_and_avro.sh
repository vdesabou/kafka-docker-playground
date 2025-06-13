## [@bashly-upgrade validations]
validate_file_exists_and_avro() {
  file="$1"

  real_file=$file
  if [[ $file == *"@"* ]]
  then
    real_file=$(echo "$file" | cut -d "@" -f 2)
  fi

  if [[ -f "$real_file" ]]; then
    return 0
  else
    logerror "<$real_file> does not correspond to the path of an existing file, please make sure to use absolute full path or correct relative path !"
    return
  fi

  if [[ "$real_file" == *.avro ]]; then
    return 0
  else
    logerror "<$real_file> is not an Avro file. Please provide a file with .avro extension."
    return
  fi
}