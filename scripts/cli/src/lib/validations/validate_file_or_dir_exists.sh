## [@bashly-upgrade validations]
validate_file_or_dir_exists() {
  file="$1"

  real_file=$file
  if [[ ! -e "$file" && $file == *"@"* ]]
  then
    real_file=$(echo "$file" | cut -d "@" -f 2)
  fi

  if [[ ! -e "$real_file" ]]; then
    logerror "<$real_file> does not correspond to an existing file or folder, please make sure to use absolute full path or correct relative path !"
    return
  fi
}
