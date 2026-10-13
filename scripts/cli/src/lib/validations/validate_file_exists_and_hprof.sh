## [@bashly-upgrade validations]
validate_file_exists_and_hprof() {
  file="$1"

  real_file=$file
  if [[ ! -f "$file" && $file == *"@"* ]]
  then
    real_file=$(echo "$file" | cut -d "@" -f 2)
  fi

  if [[ ! -f "$real_file" ]]; then
    logerror "<$real_file> does not correspond to the path of an existing file, please make sure to use absolute full path or correct relative path !"
    return
  fi

  if [[ "$real_file" != *.hprof && "$real_file" != *.hprof.gz ]]; then
    logerror "<$real_file> is not a heap dump, please provide a .hprof or .hprof.gz file"
    return
  fi
}
