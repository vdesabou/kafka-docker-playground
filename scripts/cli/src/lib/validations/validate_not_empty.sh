## [@bashly-upgrade validations]
validate_not_empty() {
  if [[ -z "$1" ]]; then
    logerror "must not be empty"
  fi
}