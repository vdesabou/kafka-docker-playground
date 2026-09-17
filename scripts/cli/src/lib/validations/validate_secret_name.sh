## Validate that the argument looks like an environment variable name
validate_secret_name() {
  if [[ "$1" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    return 0
  else
    logerror "<$1> must be an uppercase environment variable name, for example SALESFORCE_PASSWORD"
    return
  fi
}
