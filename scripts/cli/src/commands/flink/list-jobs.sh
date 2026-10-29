state="${args[--state]}"
json="${args[--json]}"

get_flink_rest_url
overview=$(curl -s -f "${flink_rest_url}/overview") || { logerror "❌ could not reach the flink rest api on $flink_rest_url"; exit 1; }
jobs=$(curl -s -f "${flink_rest_url}/jobs/overview") || { logerror "❌ could not list the jobs with ${flink_rest_url}/jobs/overview"; exit 1; }

jobs=$(echo "$jobs" | jq --arg state "$state" '[.jobs[] | select($state == "" or .state == $state)] | sort_by(-."start-time")')

if [[ -n "$json" ]]
then
    echo "$jobs"
    exit 0
fi

log "📋 Jobs of the Flink cluster (Flink $(echo "$overview" | jq -r '."flink-version"'), $flink_rest_url)"
if [ "$(echo "$jobs" | jq 'length')" == "0" ]
then
    if [[ -n "$state" ]]
    then
        log "🤷 no job in state $state"
    else
        log "🤷 no job, submit one with playground flink sql"
    fi
    exit 0
fi

{
    printf 'JOB ID\tSTATE\tNAME\tSTART\tDURATION\n'
    echo "$jobs" | jq -r '.[] |
        (.duration / 1000 | floor) as $s |
        [.jid, .state, (.name | gsub("\\s+"; " ") | if length > 60 then .[0:57] + "..." else . end),
         (."start-time" / 1000 | floor | localtime | strftime("%Y-%m-%d %H:%M:%S")),
         (if $s >= 3600 then "\($s / 3600 | floor)h\($s % 3600 / 60 | floor)m\($s % 60)s"
          elif $s >= 60 then "\($s / 60 | floor)m\($s % 60)s"
          else "\($s)s" end)] | @tsv'
} | column -t -s $'\t'

for job_id in $(echo "$jobs" | jq -r '.[] | select(.state == "FAILED") | .jid')
do
    # flink 1.x has root-exception, flink 2.x only the exception history. keep the exception and its last cause, the
    # first line alone is often "Recovery is suppressed by NoRestartBackoffTimeStrategy"
    exception=$(curl -s "${flink_rest_url}/jobs/$job_id/exceptions" | jq -r '."root-exception" // .exceptionHistory.entries[0].stacktrace // empty' 2>/dev/null | grep -E "^[^[:space:]]" | sed -n '1p;$p' | uniq)
    if [[ -n "$exception" ]]
    then
        logerror "❌ job $job_id failed with:"
        echo "$exception"
    fi
done
if echo "$jobs" | jq -e 'any(.[]; .state == "FAILED")' > /dev/null
then
    log "🎓 full stack traces: playground container logs -c $flink_jobmanager_container --errors"
fi
