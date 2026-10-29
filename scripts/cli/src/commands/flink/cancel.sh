job="${args[--job]}"
all="${args[--all]}"

get_flink_rest_url
running_jobs=$(playground get-flink-job-list)

if [[ -n "$job" ]]
then
    job_ids="$job"
elif [[ -z "$running_jobs" ]]
then
    log "🤷 no running job to cancel"
    exit 0
elif [[ -n "$all" ]] || [ "$(echo "$running_jobs" | wc -l | tr -d ' ')" == "1" ]
then
    job_ids="$running_jobs"
else
    logerror "❌ several jobs are running, choose one with --job, or cancel them all with --all:"
    playground flink list-jobs --state RUNNING
    exit 1
fi

failed=0
for job_id in $job_ids
do
    name=$(curl -s "${flink_rest_url}/jobs/$job_id" | jq -r '.name // empty' 2>/dev/null)
    if [[ -z "$name" ]]
    then
        logerror "❌ job $job_id does not exist, see playground flink list-jobs"
        failed=1
        continue
    fi
    log "🛑 Cancelling job $job_id ($name)"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "${flink_rest_url}/jobs/$job_id?mode=cancel")
    if [ "$http_code" != "202" ]
    then
        logerror "❌ could not cancel job $job_id (http code $http_code)"
        failed=1
        continue
    fi
    state=""
    for i in {1..30}
    do
        state=$(curl -s "${flink_rest_url}/jobs/$job_id" | jq -r '.state' 2>/dev/null)
        if [ "$state" == "CANCELED" ] || [ "$state" == "FINISHED" ] || [ "$state" == "FAILED" ]
        then
            break
        fi
        sleep 1
    done
    if [ "$state" == "CANCELED" ]
    then
        log "✅ Job $job_id is CANCELED"
    else
        logerror "❌ job $job_id is $state after 30 seconds"
        failed=1
    fi
done
exit $failed
