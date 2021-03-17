#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

image_versions="$1"
template_file=README-template.md
readme_file=README.md
readme_tmp_file=/tmp/README.md

cp $template_file $readme_file

for image_version in $image_versions
do
  # take first image
  latest_version=$image_version
  break
done


log "Getting ci result files"
mkdir -p ci
aws s3 cp s3://kafka-docker-playground/ci/ ci/ --recursive

declare -a CIRESULTS
for dir in $(docker run vdesabou/kafka-docker-playground-connect:${latest_version} ls /usr/share/confluent-hub-components/)
do
    log "Processing connector $dir"
    test_folders=$(grep ":${dir}:" $template_file | cut -d "(" -f 2 | cut -d ")" -f 1)

    for image_version in $image_versions
    do
      for test_folder in $test_folders
      do
        log "-> test folder $test_folder"
        image_version_no_dot=$(echo ${image_version} | sed 's/\.//g')
        CIRESULTS[$image_version_no_dot]="🤷‍♂️ not tested"
        if [ "$test_folder" != "" ]
        then
          set +e
          last_success_time=""
          for script in $test_folder/*.sh
          do
            script_name=$(basename ${script})
            if [[ "$script_name" = "stop.sh" ]]
            then
              continue
            fi

            # check for ignored scripts in scripts/tests-ignored.txt
            grep "$script_name" ${DIR}/tests-ignored.txt > /dev/null
            if [ $? = 0 ]
            then
              continue
            fi

            # check for scripts containing "repro"
            if [[ "$script_name" == *"repro"* ]]; then
              continue
            fi
            time=""
            if [ "$dir" = "kafka-connect-couchbase" ]
            then
              version="3.4.8"
            elif [ "$dir" = "confluentinc-kafka-connect-jdbc" ]
            then
              if ! version_gt ${image_version} "5.9.0"
              then
                # for version less than 6.0.0, use JDBC with same version
                # see https://github.com/vdesabou/kafka-docker-playground/issues/221
                version=${image_version}
              else
                version=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.version')
              fi
            else
              version=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.version')
            fi
            testdir=$(echo "$test_folder" | sed 's/\//-/g')
            last_success_time=$(grep "$dir" ci/${image_version}-${testdir}-${version}-${script_name} | tail -1 | cut -d "|" -f 2)
            log "dir "$dir" -> ci/${image_version}-${testdir}-${version}-${script_name}"
            if [ "$last_success_time" != "" ]
            then
              # now=$(date +%s)
              # elapsed_time=$((now-last_success_time))
              # time="$(displaytime $elapsed_time) ago"
              if [[ "$OSTYPE" == "darwin"* ]]
              then
                time=$(date -r $last_success_time +%Y-%m-%d)
              else
                time=$(date -d @$last_success_time +%Y-%m-%d)
              fi
            fi
          done
          grep "$test_folder" ${DIR}/../.github/workflows/run-regression.yml | grep -v jar > /dev/null
          if [ $? = 0 ]
          then
            title="🐛❌ ${testdir} ${version}"
            if [ "$time" == "" ]
            then
              CIRESULTS[$image_version_no_dot]="❌"
              gh issue list | grep "$title" > /dev/null
              if [ $? != 0 ]
              then
                log "Creating GH issue with title $title"
                gh issue create --title "$title" --body "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" --assignee vdesabou --label bug
              fi
            else
              CIRESULTS[$image_version_no_dot]="👍 $time"
              gh issue list | grep "$title" > /dev/null
              if [ $? = 0 ]
              then
                issue_number=$(gh issue list | grep "$title" | awk '{print $1;}')
                gh issue comment ${issue_number} --body "Issue fixed in $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
                log "Closing GH issue #${issue_number} with title $title"
                gh issue close ${issue_number}
              fi
            fi
            log "CP $image_version results ${CIRESULTS[$image_version_no_dot]}"
          fi
          set -e
        fi
      done
    done

    ci=""
    for image_version in $image_versions
    do
      image_version_no_dot=$(echo ${image_version} | sed 's/\.//g')
      ci="$ci ${CIRESULTS[$image_version_no_dot]} \|"
    done

    if [ "$dir" = "kafka-connect-couchbase" ]
    then
        sed -e "s|:${dir}:|3.4.8 \| Open Source (Couchbase) \| \| $ci |g" \
            $readme_file > $readme_tmp_file
    else
        version=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.version')
        license=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.license[0].name')
        owner=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.owner.name')
        release_date=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${dir}/manifest.json | jq -r '.release_date')
        if [ "$release_date" = "null" ]
        then
          release_date=""
        fi

        if [ "$license" = "Confluent Software Evaluation License" ]
        then
          type="Confluent Subscription"
        elif [ "$license" = "Apache License 2.0" ] || [ "$license" = "Apache 2.0" ] || [ "$license" = "Apache License, Version 2.0" ] || [ "$license" = "The Apache License, Version 2.0" ]
        then
          type="Open Source ($owner)"
        else
          type="$license"
        fi

        sed -e "s|:${dir}:|${version} \| $type \| $release_date \| $ci |g" \
            $readme_file > $readme_tmp_file
    fi
    cp $readme_tmp_file $readme_file
done
