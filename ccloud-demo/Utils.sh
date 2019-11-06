verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_ccloud_login()
{
  local cmd="$1"
  set +e
  output=$($cmd 2>&1)
  set -e
  if [ "${output}" = "Error: You must login to run that command." ] || [ "${output}" = "Error: Your session has expired. Please login again." ]; then
    echo "ERROR: This script requires ccloud to be logged in. Please execute 'ccloud login' and run again."
    exit 1
  fi
}
verify_installed "ccloud"
verify_installed "confluent"
verify_ccloud_login  "ccloud kafka cluster list"

if [ "$(ccloud prompt -f "%E")" = "(none)" ]
then
    echo "ERROR: ccloud command is badly configured: environment is not set"
    echo "Example: ccloud kafka environment list"
    echo "then: ccloud kafka environment use <environment id>"
    exit 1
fi

if [ "$(ccloud prompt -f "%K")" = "(none)" ]
then
    echo "ERROR: ccloud command is badly configured: cluster is not set"
    echo "Example: ccloud kafka cluster list"
    echo "then: ccloud kafka cluster use <cluster id>"
    exit 1
fi

if [ "$(ccloud prompt -f "%a")" = "(none)" ]
then
    echo "ERROR: ccloud command is badly configured: api key is not set"
    echo "Example: ccloud api-key store <api key> <password>"
    echo "then: ccloud api-key use <api key>"
    exit 1
fi