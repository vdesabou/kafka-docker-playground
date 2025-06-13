## [@bashly-upgrade validations]
validate_date_format() {
  if [[ ! "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
  then
    logerror "must be in format yyyy-mm-dd"
    return
  fi

  if [[ "$OSTYPE" == "darwin"* ]]
  then
    # macOS: Validate the date format
    if ! date -j -f "%Y-%m-%d" "$1" &>/dev/null
    then
      logerror "must be a valid date"
      return
    fi
  else
    # Linux: Validate the date format
    if ! date -d "$1" &>/dev/null
    then
      logerror "must be a valid date"
      return
    fi
  fi
  
  return 0
}