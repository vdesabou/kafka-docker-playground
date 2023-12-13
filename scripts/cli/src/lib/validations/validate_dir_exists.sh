## [@bashly-upgrade validations]
validate_dir_exists() {
  [[ -d "$1" ]] || logerror "<$1> must be an existing directory"
}
