#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

if [ -z "$GITHUB_TOKEN" ]
then
     logerror "GITHUB_TOKEN is not set. Export it as environment variable"
     exit 1
fi

image_versions="$1"
template_file=README-template.md
readme_file=README.md
readme_tmp_file=/tmp/README.md
gh_msg_file=/tmp/gh.txt

cp $template_file $readme_file

for image_version in $image_versions
do
  # take first image
  latest_version=$image_version
  break
done

log "Getting ci result files"
mkdir -p ci
aws s3 cp s3://kafka-docker-playground/ci/ ci/ --recursive --no-progress

declare -a CIRESULTS
test_list=$(grep "🚀 " ${DIR}/../.github/workflows/run-regression.yml | cut -d '"' -f 2 | tr '\n' ' ')
for test in $test_list
do
  is_test_failed=0
  rm -f ${gh_msg_file}
  touch ${gh_msg_file}
  if [ ! -d $test ]
  then
      # logwarn "####################################################"
      # logwarn "skipping test $test, not a directory"
      # logwarn "####################################################"
      continue
  fi

  for script in ${test}/*.sh
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
        logwarn "####################################################"
        logwarn "skipping $script_name in test $test"
        logwarn "####################################################"
        continue
    fi

    # check for scripts containing "repro"
    if [[ "$script_name" == *"repro"* ]]
    then
        logwarn "####################################################"
        logwarn "skipping reproduction model $script_name in test $test"
        logwarn "####################################################"
        continue
    fi

    connector_path=""
    if [[ "$test" == "connect"* ]]
    then
      # if it is a connector test, get connector_path
      docker_compose_file=$(grep "environment" "$script" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
      if [ "${docker_compose_file}" != "" ] && [ -f "${test}/${docker_compose_file}" ]
      then
          connector_path=$(grep "CONNECT_PLUGIN_PATH" "${test}/${docker_compose_file}" | grep -v KSQL_CONNECT_PLUGIN_PATH | cut -d "/" -f 5)
          # remove any extra comma at the end (when there are multiple connectors used, example S3 source)
          connector_path=$(echo "$connector_path" | cut -d "," -f 1)
      fi
    fi

    log "###################### 📁 ${test} 🔗 ${connector_path} #########################"

    for image_version in $image_versions
    do
      image_version_no_dot=$(echo ${image_version} | sed 's/\.//g')
      CIRESULTS[$image_version_no_dot]="🤷‍♂️ not tested"

      time=""
      version=""
      if [ "$connector_path" != "" ]
      then
        if [ "$connector_path" = "kafka-connect-couchbase" ]
        then
          version="3.4.8"
        elif [ "$connector_path" = "confluentinc-kafka-connect-jdbc" ]
        then
          if ! version_gt ${image_version} "5.9.0"
          then
            # for version less than 6.0.0, use JDBC with same version
            # see https://github.com/vdesabou/kafka-docker-playground/issues/221
            version=${image_version}
          else
            version=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.version')
          fi
        else
          version=$(docker run vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.version')
        fi
      fi
      testdir=$(echo "$test" | sed 's/\//-/g')
      ci_file="ci/${image_version}-${testdir}-${version}-${script_name}"
      if [ -f ${ci_file} ]
      then
        last_execution_time=$(grep "$connector_path" ${ci_file} | tail -1 | cut -d "|" -f 2)
        status=$(grep "$connector_path" ${ci_file} | tail -1 | cut -d "|" -f 3)
        gh_run_id=$(grep "$connector_path" ${ci_file} | tail -1 | cut -d "|" -f 4)
        if [ ! -f /tmp/${gh_run_id}.json ]
        then
          curl -s -u vdesabou:$GITHUB_TOKEN -H "Accept: application/vnd.github.v3+json" -o /tmp/${gh_run_id}.json https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=100
        fi
        v=$(echo $image_version | sed -e 's/\./[.]/g')
        html_url=$(cat /tmp/${gh_run_id}.json | jq ".jobs |= map(select(.name | test(\"${v}.*${test}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url')
        html_url=$(echo "$html_url" | sed -e 's/^"//' -e 's/"$//')
        if [ "$html_url" = "" ]; then
          logerror "Could not retrieve job url!"
          cat /tmp/${gh_run_id}.json
        fi
        if [ "$last_execution_time" != "" ]
        then
          if [[ "$OSTYPE" == "darwin"* ]]
          then
            time=$(date -r $last_execution_time +%Y-%m-%d)
          else
            time=$(date -d @$last_execution_time +%Y-%m-%d)
          fi
        fi

        if [ "$status" == "failure" ]
        then
          CIRESULTS[$image_version_no_dot]="[❌ $time]($html_url)"
          is_test_failed=1
          echo -e "🔥 CP $image_version 🔗 Link to test: $html_url\n" >> ${gh_msg_file}
        else
          CIRESULTS[$image_version_no_dot]="[👍 $time]($html_url)"
          echo -e "👍 CP $image_version 🔗 Link to test: $html_url\n" >> ${gh_msg_file}
        fi
        log "CP ${image_version} result_file: ${ci_file} results: ${CIRESULTS[$image_version_no_dot]} gh_run_id: ${gh_run_id}"
      else
        logerror "result_file: ${ci_file} does not exist !"
      fi
    done #end image_version

    # GH issues
    if [ "$html_url" != "" ]
    then
      t=$(echo ${testdir} | sed 's/-/\//')
      title="🔥 ${t}"
      if [ "$version" != "" ]
      then
        echo -e "🔢 Connector version: $version\n" >> ${gh_msg_file}
      fi
      msg=$(cat ${gh_msg_file})
      if [ $is_test_failed = 1 ]
      then
        gh issue list --limit 500 | grep "$title" > /dev/null
        if [ $? != 0 ]
        then
          log "Creating GH issue with title $title"
          gh issue create --title "$title" --body "$msg" --assignee vdesabou --label bug
        fi
      else
        gh issue list | grep "$title" > /dev/null
        if [ $? = 0 ]
        then
          issue_number=$(gh issue list | grep "$title" | awk '{print $1;}')
          echo -e "✅ Issue fixed !\n"  >> ${gh_msg_file}
          gh issue comment ${issue_number} --body "$msg"
          log "Closing GH issue #${issue_number} with title $title"
          gh issue close ${issue_number}
        fi
      fi
    fi

    ci=""
    for image_version in $image_versions
    do
      image_version_no_dot=$(echo ${image_version} | sed 's/\.//g')
      ci="$ci ${CIRESULTS[$image_version_no_dot]} \|"
    done

    if [ "$connector_path" != "" ]
    then
      if [ "$connector_path" = "kafka-connect-couchbase" ]
      then
          sed -e "s|:${connector_path}:|3.4.8 \| Open Source (Couchbase) \| \| $ci |g" \
              $readme_file > $readme_tmp_file
      else
          version=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.version')
          license=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.license[0].name')
          owner=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.owner.name')
          release_date=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.release_date')
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

          sed -e "s|:${connector_path}:|${version} \| $type \| $release_date \| $ci |g" \
              $readme_file > $readme_tmp_file
      fi
      cp $readme_tmp_file $readme_file
    fi
  done #end script
done #end test_list

# Handle connector tests which are not tested as part of CI
ci=""
for image_version in $image_versions
do
  ci="$ci 🤷‍♂️ not tested \|"
done
for connector in confluentinc-kafka-connect-servicenow confluentinc-kafka-connect-maprdb confluentinc-kafka-connect-aws-redshift
do
  version=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.version')
  license=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.license[0].name')
  owner=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.owner.name')
  release_date=$(docker run vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.release_date')
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

  sed -e "s|:${connector}:|${version} \| $type \| $release_date \| $ci |g" \
      $readme_file > $readme_tmp_file
  cp $readme_tmp_file $readme_file
done