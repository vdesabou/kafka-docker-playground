## [@bashly-upgrade validations]
validate_date_format() {
  if [[ ! "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
  then
    logerror "must be in format yyyy-mm-dd"
    return 1
  fi

  if [[ "$OSTYPE" == "darwin"* ]]
  then
    # macOS: Validate the date format
    if ! date -j -f "%Y-%m-%d" "$1" &>/dev/null
    then
      logerror "must be a valid date"
      return 1
    fi
  else
    # Linux: Validate the date format
    if ! date -d "$1" &>/dev/null
    then
      logerror "must be a valid date"
      return 1
    fi
  fi

  if [[ "$OSTYPE" == "darwin"* ]]
  then
    # macOS: Check if the date is more than one year ago
    if [[ $(date -j -f "%Y-%m-%d" "$1" +%s) -lt $(date -v-1y +%s) ]]
    then
      logerror "must be less than one year old"
      return 1
    fi
  else
    # Linux: Check if the date is more than one year ago
    if [[ $(date -d "$1" +%s) -lt $(date -d "1 year ago" +%s) ]]
    then
      logerror "must be less than one year old"
      return 1
    fi
  fi

  return 0
}