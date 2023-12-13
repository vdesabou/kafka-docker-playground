## [@bashly-upgrade validations]
validate_file_exists() {
  file="$1"
  [[ -f "$1" ]] || logerror "<$file> does not correspond to the path of an existing file, please make sure to use absolute full path or correct relative path !"
}
