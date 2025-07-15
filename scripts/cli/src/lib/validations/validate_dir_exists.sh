## [@bashly-upgrade validations]
validate_dir_exists() {
  if [[ ! -d "$1" ]]; then
    logerror "must be an existing directory"
  fi
}
