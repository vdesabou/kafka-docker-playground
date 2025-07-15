## [@bashly-upgrade validations]
validate_json() {

  tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
  trap 'rm -rf $tmp_dir' EXIT
  json_file=$tmp_dir/connector.json

  echo "$1" > $json_file

  # JSON is invalid
  if ! echo "$1" | jq -e .  > /dev/null 2>&1
  then
      set +e
      jq_output=$(jq . "$json_file" 2>&1)
      error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

      if [[ -n "$error_line" ]]; then
          logerror "❌ Invalid JSON at line $error_line"
      fi
      set -e

      if [ -z "$GITHUB_RUN_NUMBER" ]
      then
          if [[ $(type -f bat 2>&1) =~ "not found" ]]
          then
              cat -n $json_file
          else
              bat $json_file --highlight-line $error_line
          fi
      fi
      return
  fi
}
