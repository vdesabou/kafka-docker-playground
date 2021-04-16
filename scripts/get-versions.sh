#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

if [ -z "$GITHUB_TOKEN" ]
then
  logerror "GITHUB_TOKEN is not set. Export it as environment variable"
  exit 1
fi

image_versions="$1"

if [ "$image_versions" = "" ]
then
  logerror "List of CP versions is not provided as argument!"
  exit 1
fi
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

test_list=$(grep "🚀 " ${DIR}/../.github/workflows/run-regression.yml | cut -d '"' -f 2 | tr '\n' ' ')
declare -a TEST_FAILED
declare -a TEST_SUCCESS
nb_total_tests=0
nb_connector_tests=0
nb_total_fail=0
nb_total_success=0
for test in $test_list
do
  nb_tests=0
  nb_fail=0
  nb_success=0
  TEST_FAILED=()
  TEST_SUCCESS=()
  rm -f ${gh_msg_file}
  touch ${gh_msg_file}
  gh_issue_number=""
  if [ ! -d $test ]
  then
    # logwarn "####################################################"
    # logwarn "skipping test $test, not a directory"
    # logwarn "####################################################"
    continue
  fi
  log "################################"
  log "### 📁 ${test}"

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
      log "####################################################"
      log "⏭ skipping $script_name in test $test"
      log "####################################################"
      continue
    fi

    # check for scripts containing "repro"
    if [[ "$script_name" == *"repro"* ]]
    then
      log "####################################################"
      log "⏭ skipping reproduction model $script_name in test $test"
      log "####################################################"
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

    log "## 📄 ${script_name}"

    for image_version in $image_versions
    do
      let "nb_tests++"
      let "nb_total_tests++"
      image_version_no_dot=$(echo ${image_version} | sed 's/\.//g')
      time_day=""
      time_day_hour=""
      version=""
      if [ "$connector_path" != "" ]
      then
        if [ "$connector_path" = "confluentinc-kafka-connect-jdbc" ]
        then
          if ! version_gt ${image_version} "5.9.0"
          then
            # for version less than 6.0.0, use JDBC with same version
            # see https://github.com/vdesabou/kafka-docker-playground/issues/221
            version=${image_version}
          else
            version=$(docker run --rm vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.version')
          fi
        else
          version=$(docker run --rm vdesabou/kafka-docker-playground-connect:${image_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.version')
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
            time_day=$(date -r $last_execution_time "+%Y-%m-%d")
            time_day_hour=$(date -r $last_execution_time "+%Y-%m-%d %H:%M")
          else
            time_day=$(date -d @$last_execution_time "+%Y-%m-%d")
            time_day_hour=$(date -d @$last_execution_time "+%Y-%m-%d %H:%M")
          fi
        fi

        if [ "$status" == "failure" ]
        then
          let "nb_fail++"
          let "nb_total_fail++"
          TEST_FAILED[$image_version_no_dot]="[❌ $time_day]($html_url)"
          echo -e "🔥 CP $image_version 🕐 ${time_day_hour} 📄 ${script_name} 🔗 $html_url\n" >> ${gh_msg_file}
          log "🔥 CP $image_version 🕐 ${time_day_hour} 📄 ${script_name} 🔗 $html_url"
        else
          let "nb_success++"
          let "nb_total_success++"
          TEST_SUCCESS[$image_version_no_dot]="[👍 $time_day]($html_url)"
          echo -e "👍 CP $image_version 🕐 ${time_day_hour} 📄 ${script_name} 🔗 $html_url\n" >> ${gh_msg_file}
          log "👍 CP $image_version 🕐 ${time_day_hour} 📄 ${script_name} 🔗 $html_url"
        fi
      else
        logerror "result_file: ${ci_file} does not exist !"
      fi
    done #end image_version
  done #end script

  # GH issues
  if [ "$html_url" != "" ]
  then
    t=$(echo ${testdir} | sed 's/-/\//')
    title="🔥 ${t}"
    if [ "$version" != "" ]
    then
      echo -e "🔢 Connector version: $version\n" >> ${gh_msg_file}
    fi
    log "Number of successful tests: $nb_success/${nb_tests}"
    if [ ${nb_fail} -gt 0 ]
    then
      msg=$(cat ${gh_msg_file})
      gh issue list --limit 500 | grep "$title" > /dev/null
      if [ $? != 0 ]
      then
        log "Creating GH issue with title $title"
        gh issue create --title "$title" --body "$msg" --assignee vdesabou --label bug
      else
        log "GH issue with title $title already exist, adding comment..."
        issue_number=$(gh issue list --limit 500 | grep "$title" | awk '{print $1;}')
        gh issue comment ${issue_number} --body "$msg"
      fi
      gh_issue_number=$(gh issue list --limit 500 | grep "$title" | awk '{print $1;}')
    fi
    if [ ${nb_success} -eq ${nb_tests} ]
    then
      # if all scripts in tests are now successful, close the issue
      gh issue list | grep "$title" > /dev/null
      if [ $? = 0 ]
      then
        issue_number=$(gh issue list --limit 500 | grep "$title" | awk '{print $1;}')
        echo -e "✅ Issue fixed !\n"  >> ${gh_msg_file}
        msg=$(cat ${gh_msg_file})
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
    if [ "${TEST_FAILED[$image_version_no_dot]}" != "" ]
    then
      gh_issue_number=$(echo $gh_issue_number|tr -d '\n')
      if [ "${gh_issue_number}" != "" ]
      then
        ci="$ci ${TEST_FAILED[$image_version_no_dot]} [🐞 \#${gh_issue_number}](https://github.com/vdesabou/kafka-docker-playground/issues/${gh_issue_number}) \|"
      else
        ci="$ci ${TEST_FAILED[$image_version_no_dot]} \|"
      fi
    elif [ "${TEST_SUCCESS[$image_version_no_dot]}" != "" ]
    then
      ci="$ci ${TEST_SUCCESS[$image_version_no_dot]} \|"
    else
      logerror "TEST_SUCCESS and TEST_FAILED are both empty !"
    fi

  done

  if [ "$connector_path" != "" ]
  then
    version=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.version')
    license=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.license[0].name')
    owner=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.owner.name')
    release_date=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.release_date')
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

    let "nb_connector_tests++"
    sed -e "s|:${test}:|${version} \| $type \| $release_date \| $ci |g" \
        $readme_file > $readme_tmp_file

    cp $readme_tmp_file $readme_file
  fi
done #end test_list

# Handle connector tests which are not tested as part of CI
ci=""
cp_version_tested=""
for image_version in $image_versions
do
  ci="$ci 🤷‍♂️ not tested \|"
  cp_version_tested="$cp_version_tested%20$image_version"
done
for connector in confluentinc-kafka-connect-servicenow confluentinc-kafka-connect-maprdb confluentinc-kafka-connect-aws-redshift
do
  version=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.version')
  license=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.license[0].name')
  owner=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.owner.name')
  release_date=$(docker run --rm vdesabou/kafka-docker-playground-connect:${latest_version} cat /usr/share/confluent-hub-components/${connector}/manifest.json | jq -r '.release_date')
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

  let "nb_connector_tests++"
  sed -e "s|:${connector}:|${version} \| $type \| $release_date \| $ci |g" \
      $readme_file > $readme_tmp_file
  cp $readme_tmp_file $readme_file
done

tests_color="green"
if [ $nb_total_fail -gt 0 ]; then
  tests_color="red"
fi
if [[ "$OSTYPE" == "darwin"* ]]
then
  last_run=$(date "+%Y-%m-%d %H:%M")
else
  last_run=$(date "+%Y-%m-%d %H:%M")
fi
last_run=${last_run// /%20}
last_run=${last_run//-/--}
# handle shields badges
sed -e "s|:nb_total_success:|$nb_total_success|g" \
    -e "s|:nb_total_tests:|$nb_total_tests|g" \
    -e "s|:nb_connector_tests:|$nb_connector_tests|g" \
    -e "s|:cp_version_tested:|$cp_version_tested|g" \
    -e "s|:tests_color:|$tests_color|g" \
    -e "s|:last_run:|$last_run|g" \
    $readme_file > $readme_tmp_file
cp $readme_tmp_file $readme_file
