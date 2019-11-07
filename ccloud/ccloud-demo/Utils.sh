function verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
function verify_ccloud_login()
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
function verify_ccloud_details()
{
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

    CCLOUD_PROMPT_FMT='You will be using Confluent Cloud config: user={{color "green" "%u"}}, environment={{color "red" "%E"}}, cluster={{color "cyan" "%K"}}, api key={{color "yellow" "%a"}}'
    ccloud prompt -f "$CCLOUD_PROMPT_FMT"
}
function check_if_continue()
{
    read -p "Continue (y/n)?" choice
    case "$choice" in
    y|Y ) ;;
    n|N ) exit 0;;
    * ) echo "ERROR: invalid response!";exit 1;;
    esac
}
function create_topic()
{
  local topic="$1"
  echo -e "\n# Check if topic $topic exists"
  ccloud kafka topic create $topic --dry-run 2>/dev/null
  if [[ $? == 0 ]]; then
    echo -e "\n# Create topic $topic"
    echo "ccloud kafka topic create $topic"
    ccloud kafka topic create $topic || true
  else
    echo "Topic $topic already exists"
  fi
}
function delete_topic()
{
  local topic="$1"
  echo -e "\n# Check if topic $topic exists"
  ccloud kafka topic create $topic --dry-run 2>/dev/null
  if [[ $? != 0 ]]; then
    echo -e "\n# Delete topic $topic"
    echo "ccloud kafka topic delete $topic"
    ccloud kafka topic delete $topic || true
  else
    echo "Topic $topic does not exist"
  fi
}
function version_gt() {
	test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

function get_ccloud_version() {
  ccloud version | grep "^Version:" | cut -d':' -f2 | cut -d'v' -f2
}

function check_ccloud_version() {

	REQUIRED_CCLOUD_VER=${1:-"0.185.0"}
	CCLOUD_VER=$(get_ccloud_version)

	if version_gt $REQUIRED_CCLOUD_VER $CCLOUD_VER; then
		echo "ccloud version ${REQUIRED_CCLOUD_VER} or greater is required.  Current reported version: ${CCLOUD_VER}"
		echo 'To update run: ccloud update'
		exit 1
	fi
}