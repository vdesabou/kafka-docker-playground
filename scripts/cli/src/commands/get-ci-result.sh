test="${args[--test]}"
environment_flag="${args[--environment]}"
podman="${args[--podman]}"
logs="${args[--logs]}"
max_findings="${args[--max-findings]}"

if [[ -n "$test" ]]
then
    # accept a directory or a script, absolute or relative to the repository
    test="${test#$root_folder/}"
    test="${test%/}"
    if [[ "$test" == *.sh ]]
    then
        test="$(dirname "$test")"
    fi
    if [ ! -d "$root_folder/$test" ]
    then
        logerror "❌ --test $test is not an example directory of $root_folder"
        exit 1
    fi
    dir2="$test"
    environment="plaintext"
else
    test_file=$(playground state get run.test_file)
    get_environment_used

    if [ ! -f $test_file ]
    then 
        logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
        exit 1
    fi

    test_file_directory="$(dirname "${test_file}")"
    base1="${test_file_directory##*/}" # connect-cdc-oracle12-source
    dir1="${test_file_directory%/*}" #connect
    dir2="${dir1##*/}/$base1" # connect/connect-cdc-oracle12-source
fi

if [[ -n "$environment_flag" ]]
then
    environment="$environment_flag"
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if [[ "$dir2" == reproduction-models* ]]
then
    exit 0
fi

content_file="$tmp_dir/content.md"
curl -s -o $content_file  https://raw.githubusercontent.com/vdesabou/kafka-docker-playground-docs/main/docs/content.md

result_ok=""
result_fail=""

if [ "$environment" == "cfk" ]
then
    result_ok="$(grep "$dir2" $content_file | sed -n 's/.*\[CI_CFK \(ok\)\].*(\(https[^)]*\)).*/🤖CI status: 🟢 cfk ok\n🔗test url: \2/p')"
    result_fail="$(grep "$dir2" $content_file | sed -n 's/.*\[CI_CFK \(fail\)\].*(\(https[^)]*\)).*/🤖CI status: 🔴 cfk fail\n🐛 github issue: \2/p')"

    # Backward-compatible fallback when CI_CFK badge is missing.
    if [ -z "$result_ok" ] && [ -z "$result_fail" ]
    then
        result_ok="$(grep "$dir2" $content_file | sed -n 's/.*\[CI \(ok\)\].*(\(https[^)]*\)).*/🤖CI status: 🟢 ok\n🔗test url: \2/p')"
        result_fail="$(grep "$dir2" $content_file | sed -n 's/.*\[CI \(fail\)\].*(\(https[^)]*\)).*/🤖CI status: 🔴 fail\n🐛 github issue: \2/p')"
    fi
else
    result_ok="$(grep "$dir2" $content_file | sed -n 's/.*\[CI \(ok\)\].*(\(https[^)]*\)).*/🤖CI status: 🟢 ok\n🔗test url: \2/p')"
    result_fail="$(grep "$dir2" $content_file | sed -n 's/.*\[CI \(fail\)\].*(\(https[^)]*\)).*/🤖CI status: 🔴 fail\n🐛 github issue: \2/p')"
fi

result_not_tested="$(grep "$dir2" $content_file | sed -n 's/.*\[not tested\].*/🤖CI status: 🤷‍♂️ not tested/p')"

# print only result not empty
if [ -n "$result_ok" ]
then
    log "$result_ok"
fi

if [ -n "$result_fail" ]
then
    logwarn "$result_fail"
fi

if [ -n "$result_not_tested" ]
then
    log "$result_not_tested"
fi

if [[ ! -n "$logs" ]]
then
    exit 0
fi

if [[ $(type -f gh 2>&1) =~ "not found" ]]
then
    logerror "❌ --logs needs the GitHub CLI, visit https://cli.github.com/manual/installation to install"
    exit 1
fi

repo="vdesabou/kafka-docker-playground"

# CI issue titles, see scripts/run-tests.sh
title="🔥 $dir2"
job_suffix_regex=" plaintext ?$"
job_label="plaintext"
if [ "$environment" == "cfk" ] && [[ -n "$podman" ]]
then
    title="🔥 $dir2 (cfk, podman)"
    job_suffix_regex=" cfk 🦭$"
    job_label="cfk 🦭"
elif [ "$environment" == "cfk" ]
then
    title="🔥 $dir2 (cfk)"
    job_suffix_regex=" cfk ?$"
    job_label="cfk"
elif [[ -n "$podman" ]]
then
    title="🔥 $dir2 (podman)"
    job_suffix_regex=" plaintext 🦭$"
    job_label="plaintext 🦭"
fi

issue_number=$(gh issue list --repo "$repo" --state open --search "\"$title\" in:title" --json number,title --limit 50 2>/dev/null | jq -r --arg title "$title" '.[] | select(.title == $title) | .number' | head -1)
if [ -z "$issue_number" ]
then
    log "✅ no open CI issue <$title>: no failure logs to show"
    exit 0
fi

# the latest CI occurrence: body or comment with a job url (human or triage comments have none)
occurrence=$(gh issue view "$issue_number" --repo "$repo" --json body,comments -q '[.body] + [.comments[].body] | map(select(test("/actions/runs/[0-9]+/job/[0-9]+"))) | last')
job_url=$(echo "$occurrence" | grep -oE "https://github.com/$repo/actions/runs/[0-9]+/job/[0-9]+" | tail -1)
if [ -z "$job_url" ]
then
    logerror "❌ no CI job url found in issue #$issue_number (https://github.com/$repo/issues/$issue_number)"
    exit 1
fi
run_id=$(echo "$job_url" | sed -E 's#.*/runs/([0-9]+)/job/.*#\1#')

# issues often link a sibling job of the same run: pick the one running this example in this environment
run_json=$(gh run view "$run_id" --repo "$repo" --json jobs,headSha,createdAt 2>/dev/null)
job_id=$(echo "$run_json" | jq -r --arg dir "$dir2" --arg suffix "$job_suffix_regex" '[.jobs[] | select(.name | contains(" " + $dir + " ")) | select(.name | test($suffix))][0].databaseId // empty')
if [ -z "$job_id" ]
then
    # the linked job runs other examples: reading it would only show unrelated scripts
    logwarn "🤷 issue #$issue_number links run $run_id, which has no '$job_label' job running $dir2: the issue may be stale (reported from another run's result)"
    echo "   🔗 $job_url"
    echo "   🐛 https://github.com/$repo/issues/$issue_number"
    exit 0
fi
head_sha=$(echo "$run_json" | jq -r '.headSha // empty')
run_date=$(echo "$run_json" | jq -r '.createdAt // empty')

header=$(echo "$occurrence" | grep -m1 -E "^🔥 CP " | sed -E 's/ 📄.*//')
log "🔥 latest failure reported in https://github.com/$repo/issues/$issue_number"
if [ -n "$header" ]
then
    echo "   $header"
fi
echo "   🔗 https://github.com/$repo/actions/runs/$run_id/job/$job_id"
echo "   🕐 run of $run_date on commit ${head_sha:0:9}"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# the full log: 'gh run view --log' truncates long jobs
if ! gh api --allow-escape-sequences "repos/$repo/actions/jobs/$job_id/logs" > "$tmp_dir/job.log" 2> "$tmp_dir/error.log"
then
    logerror "❌ could not download the log of job $job_id (logs are kept 90 days)"
    cat "$tmp_dir/error.log"
    exit 1
fi
sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z //' -e 's/\x1b\[[0-9;]*m//g' "$tmp_dir/job.log" > "$tmp_dir/clean.log"

# one section per script of the example: from "Executing <script> in dir <dir>" to its RESULT line
awk -v dir="$dir2" -v out="$tmp_dir/section" '
    index($0, "🚀 Executing ") && index($0, " in dir " dir) && $0 ~ (" in dir " dir "$") {
        script = $0
        sub(/^.*🚀 Executing /, "", script)
        sub(/ in dir .*$/, "", script)
        n++
        file = out "-" n
        print script > (out "-" n ".name")
        close(out "-" n ".name")
        capture = 1
    }
    capture { print > file }
    capture && index($0, "RESULT: ") && index($0, " in dir " dir " ") {
        if (index($0, "RESULT: FAILURE")) print "failure" > (file ".status")
        else print "other" > (file ".status")
        close(file ".status")
        close(file)
        capture = 0
    }
' "$tmp_dir/clean.log"

nb_failures=0
for status_file in "$tmp_dir"/section-*.status
do
    [ -f "$status_file" ] || continue
    if [ "$(cat "$status_file")" != "failure" ]
    then
        continue
    fi
    section="${status_file%.status}"
    script=$(cat "$section.name")
    nb_failures=$((nb_failures+1))
    echo ""
    log "🔥 $script failed, last lines before the failure:"
    awk '/RESULT: FAILURE for .* \(took/ { exit } { print }' "$section" | tail -25 | sed 's/^/   /'
    echo ""
    log "🔎 ERROR/FATAL digest of $script in the CI job"
    # the runner's own failure messages are already shown above, keep the causes
    grep -v -E "RESULT: FAILURE|has failed after [0-9]+ attempts|^playground container display-error-all$|🔥 #+$" "$section" \
        | summarize_log_errors "$max_findings" \
        | sed 's/ or narrow with --since$//'
done

if [ $nb_failures -eq 0 ]
then
    nb_passed=$(ls "$tmp_dir"/section-*.status 2>/dev/null | wc -l | tr -d ' ')
    if [ "$nb_passed" -gt 0 ]
    then
        log "✅ the $nb_passed script(s) of $dir2 run in job $job_id passed: issue #$issue_number may be stale (fixed since, or reported from an older result)"
    else
        logwarn "🤷 no script of $dir2 ran to completion in job $job_id, it may have been cancelled or timed out. Full log: gh api repos/$repo/actions/jobs/$job_id/logs"
    fi
fi
