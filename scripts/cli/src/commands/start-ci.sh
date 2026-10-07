test_list="${args[--test-list]:-}"
all_failing="${args[--all-failing]:-}"
cfk="${args[--cfk]:-}"
podman="${args[--podman]:-}"

if ! command -v gh >/dev/null 2>&1
then
	logerror "❌ gh CLI is required to trigger CI"
	exit 1
fi

if [[ -n "$cfk" ]]
then
	playground_environment="cfk"
else
	playground_environment=""
fi

if [[ -z "$test_list" ]] || [[ -n "$all_failing" ]]
then
	issue_args=(issue list --state open --limit 500 --label "CI failing 🔥" --json title)
	if [[ -n "$cfk" ]]
	then
		issue_args+=(--label cfk)
	fi
	# podman failures have their own issues, titled "(podman)" or "(cfk, podman)":
	# --podman re-runs those, and a docker re-run leaves them out
	if [[ -n "$podman" ]]
	then
		issue_args+=(--label podman)
	fi

	issues_json=$(gh "${issue_args[@]}")
	test_list=$(printf '%s\n' "$issues_json" | jq -r --arg podman "$podman" '
		.[]
		| .title
		| select(if $podman == "" then (test("podman\\)$") | not) else true end)
		| sub("^🔥[[:space:]]+"; "")
		| sub("[[:space:]]*\\((cfk|podman|cfk, podman)\\)$"; "")
	' | awk 'NF && !seen[$0]++' | paste -sd ' ' -)
fi

if [[ -z "$test_list" ]]
then
	logerror "❌ No failing tests were found in GitHub issues"
	exit 1
fi

ref="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$ref" ]]
then
	ref="master"
fi

workflow_args=(workflow run ci.yml --ref "$ref" -f test_name="$test_list")
if [[ -n "$playground_environment" ]]
then
	workflow_args+=(-f playground_environment="$playground_environment")
fi
if [[ -n "$podman" ]]
then
	workflow_args+=(-f container_engine=podman)
fi

log "Triggering CI workflow with test_name=$test_list"
if [[ -n "$playground_environment" ]]
then
	log "Using playground_environment=$playground_environment"
fi
if [[ -n "$podman" ]]
then
	log "Using container_engine=podman"
fi

gh "${workflow_args[@]}"