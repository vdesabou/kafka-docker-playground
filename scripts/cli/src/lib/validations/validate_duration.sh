validate_duration() {
  if [[ "$1" =~ ^[0-9]+[smh]?$ ]]
  then
    return 0
  else
    echo "must be a duration in seconds, or with a s, m or h suffix (e.g. 30s, 5m)"
    return
  fi
}
