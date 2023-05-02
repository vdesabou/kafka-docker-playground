## [@bashly-upgrade validations]
validate_editor_exists() {
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]
  then
    echo "this script requires $cmd. Please install $cmd and run again."
  fi
}


