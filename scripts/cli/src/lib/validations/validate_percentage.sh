## [@bashly-upgrade validations]
validate_percentage() {
  if [[ ! "$1" =~ ^[0-9]+$ ]]
  then
    logerror "must be an integer"
    return 1
  fi

  if [[ "$1" -lt 0 ]] || [[ "$1" -gt 100 ]]
  then
    logerror "must be between 0 and 100"
    return 1
  fi
}