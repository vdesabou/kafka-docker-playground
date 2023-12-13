## [@bashly-upgrade validations]
validate_not_empty() {
  [[ -z "$1" ]] && logerror "must not be empty"
}
