## [@bashly-upgrade validations]
validate_file_exists() {
  file="$1"
  if [[ -f "$1" ]]; then
    return 0
  else
    logerror "<$file> does not correspond to the path of an existing file, please make sure to use absolute full path or correct relative path !"
    return
  fi
}
