job="${args[--job]}"
no_open="${args[--no-open]}"

get_flink_environment
if [[ "$flink_environment" == "ccloud" ]]
then
    logerror "❌ the Flink statements of Confluent Cloud are in the Confluent Cloud console (Environments > Flink), there is no Flink UI"
    exit 1
fi

if ! get_flink_rest_url
then
    logerror "❌ the Flink cluster is not running: start an example with --enable-flink (or ENABLE_FLINK=true), see flink/flink-sql-kafka"
    exit 1
fi

url="$flink_rest_url"
if [[ -n "$job" ]]
then
    job_state=$(curl -s -f "${flink_rest_url}/jobs/${job}" | jq -r '.state // empty' 2> /dev/null)
    if [[ -z "$job_state" ]]
    then
        logerror "❌ no job $job in the Flink cluster, see playground flink list-jobs"
        exit 1
    fi
    # the UI has one page per job: running/<id> while it runs, completed/<id> once it is FINISHED, CANCELED or FAILED
    case "$job_state" in
        FINISHED|CANCELED|FAILED) url="${flink_rest_url}/#/job/completed/${job}/overview" ;;
        *) url="${flink_rest_url}/#/job/running/${job}/overview" ;;
    esac
    log "🌐 Flink UI, job $job ($job_state): $url"
else
    log "🌐 Flink UI: $url"
fi

if [[ -z "$no_open" ]] && [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ]
then
    open_url "$url" || true
fi
