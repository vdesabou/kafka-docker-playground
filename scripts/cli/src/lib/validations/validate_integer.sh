## [@bashly-upgrade validations]
validate_integer() {
  if [[ "$1" == "-1" ]] || [[ "$1" =~ ^[0-9]+$ ]]
  then
    return 0
  else
    echo "must be an integer"
    return 1
  fi
}