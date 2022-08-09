#!/bin/bash

tag="$2"
if [ "$tag" != "" ]
then
    export TAG=$tag
fi

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

# go to root folder
cd ${DIR}/..

nb_test_failed=0
nb_test_skipped=0
failed_tests=""
skipped_tests=""

test_list="$1"
if [ "$1" = "ALL" ]
then
    test_list=$(grep "🚀 " ${DIR}/../.github/workflows/ci.yml | cut -d '"' -f 2 | tr '\n' ' ')
fi

for dir in $test_list
do
    if [ ! -d $dir ]
    then
        log "####################################################"
        log "⏭ skipping dir $dir, not a directory"
        log "####################################################"
        continue
    fi

    cd $dir > /dev/null

    curl -s https://raw.githubusercontent.com/vdesabou/kafka-docker-playground-connect/master/README.md -o /tmp/README.txt
    for script in *.sh
    do
        if [[ "$script" = "stop.sh" ]]
        then
            continue
        fi

        # check for ignored scripts in scripts/tests-ignored.txt
        grep "$script" ${DIR}/tests-ignored.txt > /dev/null
        if [ $? = 0 ]
        then
            log "####################################################"
            log "⏭ skipping $script in dir $dir"
            log "####################################################"
            continue
        fi

        # check for scripts containing "repro"
        if [[ "$script" == *"repro"* ]]; then
            log "####################################################"
            log "⏭ skipping reproduction model $script in dir $dir"
            log "####################################################"
            continue
        fi

        log "####################################################"
        log "🕹 processing $script in dir $dir"
        log "####################################################"

        THE_CONNECTOR_TAG=""
        if [[ "$dir" == "connect"* ]]
        then
            docker_compose_file=$(grep "environment" "$script" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
            if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
            then
                connector_path=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | cut -d "/" -f 5 | head -1)
                # remove any extra comma at the end (when there are multiple connectors used, example S3 source)
                connector_path=$(echo "$connector_path" | cut -d "," -f 1)
                owner=$(echo "$connector_path" | cut -d "-" -f 1)
                name=$(echo "$connector_path" | cut -d "-" -f 2-)

                if [ "$connector_path" != "" ]
                then
                    THE_CONNECTOR_TAG=$(grep "$connector_path " /tmp/README.txt | cut -d "|" -f 3 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')

                    if [ "$connector_path" = "confluentinc-kafka-connect-jdbc" ]
                    then
                        if ! version_gt ${TAG} "5.9.0"
                        then
                            # for version less than 6.0.0, use JDBC with same version
                            # see https://github.com/vdesabou/kafka-docker-playground/issues/221
                            THE_CONNECTOR_TAG=${TAG}
                        fi
                    fi
                fi
            fi
        fi
        testdir=$(echo "$dir" | sed 's/\//-/g')
        file="$TAG-$testdir-$THE_CONNECTOR_TAG-$script"
        s3_file="s3://kafka-docker-playground/ci/$file"
        set +e
        exists=$(aws s3 ls $s3_file --region us-east-1)
        if [ -z "$exists" ]; then
            # log "DEBUG: $s3_file does not exist, run the test"
            :
        else
            aws s3 cp $s3_file . --region us-east-1
            if [ ! -f $file ]
            then
                logwarn "Error getting $s3_file"
                elapsed_time=999999999999
            else
                file_content=$(cat $file)
                last_execution_time=$(cat $file | tail -1 | cut -d "|" -f 2)
                status=$(cat $file | tail -1 | cut -d "|" -f 3)
                now=$(date +%s)
                elapsed_time=$((now-last_execution_time))

                gh_run_id=$(grep "$connector_path" ${file} | tail -1 | cut -d "|" -f 4)
                if [ ! -f /tmp/${gh_run_id}_1.json ]
                then
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_1.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=1"
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_2.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=2"
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_3.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=3"
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_4.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=4"
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_5.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=5"
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_6.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=6"
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_7.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=7"
                    curl -s -u vdesabou:$CI_GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o "/tmp/${gh_run_id}_8.json" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100&page=8"
                fi
                v=$(echo $tag | sed -e 's/\./[.]/g')
                html_url=$(cat "/tmp/${gh_run_id}_1.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                then
                    html_url=$(cat "/tmp/${gh_run_id}_2.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                    html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                    if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                    then
                        html_url=$(cat "/tmp/${gh_run_id}_3.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                        html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                        if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                        then
                            html_url=$(cat "/tmp/${gh_run_id}_4.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                            html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                            if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                            then
                                html_url=$(cat "/tmp/${gh_run_id}_5.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                                html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                                if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                                then
                                    html_url=$(cat "/tmp/${gh_run_id}_6.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                                    html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                                    if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                                    then
                                        html_url=$(cat "/tmp/${gh_run_id}_7.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                                        html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                                        if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                                        then
                                            html_url=$(cat "/tmp/${gh_run_id}_8.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${dir}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
                                            html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
                                            if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
                                            then
                                                logerror "ERROR: Could not retrieve job url!"
                                            fi
                                        fi
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
            fi

            # for servicenow tests, run tests at least every 4 days
            if [[ "$dir" == "connect/connect-servicenow-"* ]] && [[ $elapsed_time -gt 322560 ]]
            then
                log "####################################################"
                log "⌛ Test with CP $TAG and connector $THE_CONNECTOR_TAG has already been executed successfully $(displaytime $elapsed_time) ago, more than 4 days ago...re-running. Test url: $html_url"
                log "####################################################"
                aws s3 rm $s3_file --region us-east-1
            # run at least every 14 days, even with no changes
            elif [[ $elapsed_time -gt 1209600 ]]
            then
                log "####################################################"
                log "⌛ Test with CP $TAG and connector $THE_CONNECTOR_TAG has already been executed successfully $(displaytime $elapsed_time) ago, more than 14 days ago...re-running. Test url: $html_url"
                log "####################################################"
                aws s3 rm $s3_file --region us-east-1
            elif [ "$status" = "failure" ]
            then
                log "####################################################"
                log "🔥 Test with CP $TAG and connector $THE_CONNECTOR_TAG was failing $(displaytime $elapsed_time) ago...re-running. Test url: $html_url"
                log "####################################################"
                aws s3 rm $s3_file --region us-east-1
            else
                # get last commit time unix timestamp for the folder
                now=$(date +%s)
                last_git_commit=$(git log --format=%ct  -- ${DIR}/../${dir} | head -1)
                if [[ $last_git_commit -gt $last_execution_time ]]
                then
                    elapsed_git_time=$((now-last_git_commit))
                    log "####################################################"
                    log "🆕 Test with CP $TAG and connector $THE_CONNECTOR_TAG has already been executed successfully $(displaytime $elapsed_time) ago, but a change has been noticed $(displaytime $elapsed_git_time) ago. Test url: $html_url"
                    log "####################################################"
                    aws s3 rm $s3_file --region us-east-1
                else
                    log "####################################################"
                    log "✅ Skipping as test with CP $TAG and connector $THE_CONNECTOR_TAG has already been executed successfully $(displaytime $elapsed_time) ago. Test url: $html_url"
                    log "####################################################"
                    skipped_tests=$skipped_tests"$dir[$script]\n"
                    let "nb_test_skipped++"
                    continue
                fi
            fi
        fi

        log "####################################################"
        log "🚀 Executing $script in dir $dir"
        log "####################################################"
        SECONDS=0
        retry bash $script
        ret=$?
        ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
        let ELAPSED_TOTAL+=$SECONDS
        CUMULATED="cumulated time: $((($ELAPSED_TOTAL / 60) % 60))min $(($ELAPSED_TOTAL % 60))sec"
        testdir=$(echo "$dir" | sed 's/\//-/g')
        file="$TAG-$testdir-$THE_CONNECTOR_TAG-$script"
        rm -f $file
        touch $file
        if [ $ret -eq 0 ]
        then
            log "####################################################"
            log "✅ RESULT: SUCCESS for $script in dir $dir ($ELAPSED - $CUMULATED)"
            log "####################################################"

            echo "$connector_path|`date +%s`|success|$GITHUB_RUN_ID" > $file
        elif [ $ret -eq 107 ]
        then
            log "####################################################"
            log "💀 RESULT: KNOWN ISSUE #907 for $script in dir $dir ($ELAPSED - $CUMULATED)"
            log "####################################################"

            echo "$connector_path|`date +%s`|known_issue#907|$GITHUB_RUN_ID" > $file
        elif [ $ret -eq 111 ]
        then
            log "####################################################"
            log "⏭ RESULT: SKIPPED for $script in dir $dir ($ELAPSED - $CUMULATED)"
            log "####################################################"

            echo "$connector_path|`date +%s`|skipped|$GITHUB_RUN_ID" > $file
        else
            logerror "####################################################"
            logerror "🔥 RESULT: FAILURE for $script in dir $dir ($ELAPSED - $CUMULATED)"
            logerror "####################################################"

            echo "$connector_path|`date +%s`|failure|$GITHUB_RUN_ID" > $file

            display_docker_container_error_log

            failed_tests=$failed_tests"$dir[$script]\n"
            let "nb_test_failed++"
        fi
        if [ -f "$file" ]
        then
            aws s3 cp "$file" "s3://kafka-docker-playground/ci/" --region us-east-1
            log "📄 INFO: <$file> was uploaded to S3 bucket"
        else
            logerror "ERROR: $file could not be created"
            exit 1
        fi
        bash stop.sh
    done
    cd - > /dev/null
done

if [ $nb_test_failed -eq 0 ]
then
    log "####################################################"
    log "✅ RESULT: SUCCESS"
    log "####################################################"
else
    logerror "####################################################"
    logerror "🔥 RESULT: FAILED $nb_test_failed tests failed:\n$failed_tests"
    logerror "####################################################"
    exit $nb_test_failed
fi

if [ $nb_test_skipped -ne 0 ]
then
    log "####################################################"
    log "⏭ RESULT: SKIPPED $nb_test_skipped tests skipped:\n$skipped_tests"
    log "####################################################"
fi
exit 0
