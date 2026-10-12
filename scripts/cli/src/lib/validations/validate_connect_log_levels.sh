## Validate a comma separated list of <package>=<level>, for example io.confluent.connect.s3=TRACE,org.apache.kafka.connect=DEBUG
validate_connect_log_levels() {
  for entry in ${1//,/ }
  do
    if [[ ! "$entry" =~ ^[A-Za-z0-9_.$-]+=(INFO|WARN|DEBUG|TRACE)$ ]]
    then
      logerror "<$entry> must be <package>=<level>, with level one of INFO, WARN, DEBUG, TRACE (example: io.confluent.connect.s3=TRACE)"
      return
    fi
  done
  return 0
}
