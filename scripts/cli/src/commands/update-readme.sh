tags="${args[--tags]}"
generate_for_kb="${args[--generate-for-kb]}"

set +e
tmp_dir="/tmp/update-readme"
rm -rf $tmp_dir
mkdir -p "$tmp_dir"
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

cd ${root_folder}

content_template_file=./docs/content-template.md
content_file=./docs/content.md
content_tmp_file=$tmp_dir/content.md
badges_template_file=./docs/badges-template.md
badges_file=./docs/badges.md
badges_tmp_file=$tmp_dir/badges.md
gh_msg_file=$tmp_dir/gh.txt
gh_msg_file_intro=$tmp_dir/gh_intro.txt

cp $content_template_file $content_file
cp $badges_template_file $badges_file

curl -s https://raw.githubusercontent.com/vdesabou/kafka-docker-playground-connect/master/README.md -o $tmp_dir/README.txt

ci_folder="$tmp_dir/ci"
log "Getting ci result files"
rm -rf "$ci_folder"
mkdir -p "$ci_folder"
aws s3 cp --only-show-errors s3://kafka-docker-playground/ci/ "${ci_folder}/" --recursive --no-progress --region us-east-1

test_list=$(grep "🚀" ${root_folder}/.github/workflows/ci.yml | cut -d '"' -f 2 | tr '\n' ' ')
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
  TEST_SKIPPED=()
  rm -f ${gh_msg_file}
  touch ${gh_msg_file}
  rm -f ${gh_msg_file_intro}
  touch ${gh_msg_file_intro}
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
    grep "$script_name" ${root_folder}/scripts/tests-ignored.txt > /dev/null
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
      docker_compose_file=$(grep "start-environment" "$script" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
      if [ "${docker_compose_file}" != "" ] && [ -f "${test}/${docker_compose_file}" ]
      then
        connector_path=$(grep "CONNECT_PLUGIN_PATH" "${test}/${docker_compose_file}" | grep -v KSQL_CONNECT_PLUGIN_PATH | cut -d "/" -f 5)
        # remove any extra comma at the end (when there are multiple connectors used, example S3 source)
        connector_path=$(echo "$connector_path" | cut -d "," -f 1)
      fi
    fi

    log "## 📄 ${script_name}"

    for image_version in $tags
    do
      let "nb_tests++"
      let "nb_total_tests++"
      image_version_no_dot=$(echo ${image_version} | sed 's/\.//g')
      time_day=""
      time_day_hour=""
      version=""
      release_date=""
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
            version=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 3 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
            release_date=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 6 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
          fi
        else
          version=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 3 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
          release_date=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 6 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
        fi
      fi
      if [ "$release_date" = "null" ]
      then
        release_date=""
      fi
      testdir=$(echo "$test" | sed 's/\//-/g')
      ci_file="${ci_folder}/${image_version}-${testdir}-${version}-${script_name}"

      if [ -f ${ci_file} ]
      then
        last_execution_time=$(grep "$connector_path" ${ci_file} | tail -1 | cut -d "|" -f 2)
        status=$(grep "$connector_path" ${ci_file} | tail -1 | cut -d "|" -f 3)
        gh_run_id=$(grep "$connector_path" ${ci_file} | tail -1 | cut -d "|" -f 4)
        
        if [ ! -f $tmp_dir/${gh_run_id}_1.json ]
        then
          for i in {1..10}
          do  
              # https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#get-a-workflow-run
              curl_output=$(curl -s -o $tmp_dir/${gh_run_id}_${i}.json -w %{http_code} -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28"  -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=50&page=${i}")
              if [ $curl_output -ne 200 ]
              then
                  logerror "❌ curl request <https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/runs/${gh_run_id}/jobs?per_page=50&page=${i}> failed with error code $curl_output!"
                  cat "/tmp/${gh_run_id}_${i}.json"
                  continue
              fi
          done
        fi
        
        v=$(echo $image_version | sed -e 's/\./[.]/g')
        for i in {1..10}
        do
          html_url=$(cat "$tmp_dir/${gh_run_id}_${i}.json" | jq ".jobs |= map(select(.name | test(\"${v}.*${test}\")))" | jq '[.jobs | .[] | {name: .name, html_url: .html_url }]' | jq '.[0].html_url' | sed -e 's/^"//' -e 's/"$//')
          if [ "$html_url" != "" ] && [ "$html_url" != "null" ]; then 
              break
          fi
        done

        if [ "$html_url" = "" ] || [ "$html_url" = "null" ]
        then
          logerror "Could not retrieve job url! FIXTTHIS: NOT Forcing re-run for next time..."
          # s3_file="s3://kafka-docker-playground/ci/${image_version}-${testdir}-${version}-${script_name}"
          # aws s3 rm $s3_file --region us-east-1
        fi
      else
        logerror "result_file: ${ci_file} does not exist !"
        continue
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

      connector_version=""
      if [ "$version" != "" ]
      then
        if [ "$release_date" != "" ]
        then
          connector_version=" 🔢 Connector v$version (📅 release date $release_date)"
        else
          connector_version=" 🔢 Connector v$version"
        fi
      fi
      if [ "$status" == "failure" ]
      then
        let "nb_fail++"
        let "nb_total_fail++"
        TEST_FAILED[$image_version_no_dot]="[![CP $image_version](https://img.shields.io/badge/$nb_success/$nb_tests-CP%20$image_version-red)]($html_url)"
        echo -e "🔥 CP ${image_version}${connector_version} 🕐 ${time_day_hour} 📄 [${script_name}](https://github.com/vdesabou/kafka-docker-playground/blob/master/$test/$script_name) 🔗 $html_url\n" >> ${gh_msg_file}
        log "🔥 CP $image_version 🕐 ${time_day_hour} 📄 ${script_name} 🔗 $html_url"
      elif [[ "$status" = known_issue* ]]
      then
        let "nb_success++"
        let "nb_total_success++"
        known_issue_gh_issue_number=$(echo "$status" | cut -d "#" -f 2)
        TEST_SUCCESS[$image_version_no_dot]="[![CP $image_version](https://img.shields.io/badge/known%20issue-CP%20$image_version-orange)](https://github.com/vdesabou/kafka-docker-playground/issues/$known_issue_gh_issue_number)"
        
        echo -e "💀 known issue 🐞 [#${known_issue_gh_issue_number}](https://github.com/vdesabou/kafka-docker-playground/issues/${known_issue_gh_issue_number}) CP ${image_version}${connector_version} 🕐 ${time_day_hour} 📄 [${script_name}](https://github.com/vdesabou/kafka-docker-playground/blob/master/$test/$script_name) 🔗 $html_url\n" >> ${gh_msg_file}
        log "💀 known issue 🐞 [#${known_issue_gh_issue_number}](https://github.com/vdesabou/kafka-docker-playground/issues/${known_issue_gh_issue_number}) CP ${image_version}${connector_version} 🕐 ${time_day_hour} 📄 [${script_name}](https://github.com/vdesabou/kafka-docker-playground/blob/master/$test/$script_name) 🔗 $html_url"
      elif [ "$status" == "skipped" ]
      then
        let "nb_success++"
        let "nb_total_success++"
        TEST_SKIPPED[$image_version_no_dot]="[![CP $image_version](https://img.shields.io/badge/skipped-CP%20$image_version-lightgrey)]($html_url)"
        echo -e "⏭ SKIPPED CP ${image_version}${connector_version} 🕐 ${time_day_hour} 📄 [${script_name}](https://github.com/vdesabou/kafka-docker-playground/blob/master/$test/$script_name) 🔗 $html_url\n" >> ${gh_msg_file}
        log "⏭ SKIPPED CP $image_version 🕐 ${time_day_hour} 📄 ${script_name} 🔗 $html_url"
      else
        let "nb_success++"
        let "nb_total_success++"
        TEST_SUCCESS[$image_version_no_dot]="$html_url"
        echo -e "👍 CP ${image_version}${connector_version} 🕐 ${time_day_hour} 📄 [${script_name}](https://github.com/vdesabou/kafka-docker-playground/blob/master/$test/$script_name) 🔗 $html_url\n" >> ${gh_msg_file}
        log "👍 CP $image_version 🕐 ${time_day_hour} 📄 ${script_name} 🔗 $html_url"
      fi
    done #end image_version
  done #end script

  if [[ ! -n "$generate_for_kb" ]]
  then
    # GH issues
    if [ "$html_url" != "" ]
    then
      t=$(echo ${testdir} | sed 's/-/\//')
      title="🔥 ${t}"
      log "Number of successful tests: $nb_success/${nb_tests}"
      if [ ${nb_fail} -gt 0 ]
      then
        gh issue list --limit 500 | grep "$title" > /dev/null
        if [ $? != 0 ]
        then
          echo -e "🆕💥 New issue !\n" >> ${gh_msg_file_intro}
          msg=$(cat ${gh_msg_file_intro} ${gh_msg_file})
          log "Creating GH issue with title $title"
          gh issue create --title "$title" --body "$msg" --assignee vdesabou --label "new 🆕"
        else
          echo -e "🤦‍♂️💥 Still failing !\n" >> ${gh_msg_file_intro}
          msg=$(cat ${gh_msg_file_intro} ${gh_msg_file})
          log "GH issue with title $title already exist, adding comment..."
          issue_number=$(gh issue list --limit 500 | grep "$title" | awk '{print $1;}')
          gh issue comment ${issue_number} --body "$msg"
          gh issue edit ${issue_number} --add-label "CI failing 🔥" --remove-label "new 🆕"
        fi
        gh_issue_number=$(gh issue list --limit 500 | grep "$title" | awk '{print $1;}')
      fi
      if [ ${nb_success} -eq ${nb_tests} ]
      then
        # if all scripts in tests are now successful, close the issue
        gh issue list --limit 500 | grep "$title" > /dev/null
        if [ $? = 0 ]
        then
          issue_number=$(gh issue list --limit 500 | grep "$title" | head -1 | awk '{print $1;}')
          echo -e "👍✅ Issue fixed !\n" >> ${gh_msg_file_intro}
          msg=$(cat ${gh_msg_file_intro} ${gh_msg_file})
          gh issue comment ${issue_number} --body "$msg"
          log "Closing GH issue #${issue_number} with title $title"
          gh issue close ${issue_number}
        fi
      fi
    fi

    ci=""
    ci_nb_fail=0
    ci_nb_skipped=0
    nb_image_versions=0
    for image_version in $tags
    do
      let "nb_image_versions++"
      image_version_no_dot=$(echo ${image_version} | sed 's/\.//g')
      if [ "${TEST_FAILED[$image_version_no_dot]}" != "" ]
      then
        gh_issue_number=$(echo $gh_issue_number|tr -d '\n')
        if [ "${gh_issue_number}" != "" ]
        then
          ci="$ci [![issue $gh_issue_number](https://img.shields.io/badge/$nb_success/$nb_tests-CP%20$image_version-red)](https://github.com/vdesabou/kafka-docker-playground/issues/$gh_issue_number)"
        else
          ci="$ci ${TEST_FAILED[$image_version_no_dot]}"
        fi
        let "ci_nb_fail++"
      elif [ "${TEST_SKIPPED[$image_version_no_dot]}" != "" ]
      then
        ci="$ci ${TEST_SKIPPED[$image_version_no_dot]}"
        let "ci_nb_skipped++"
      elif [ "${TEST_SUCCESS[$image_version_no_dot]}" != "" ]
      then
        ci="$ci [![CP $image_version](https://img.shields.io/badge/$nb_success/$nb_tests-CP%20$image_version-green)](${TEST_SUCCESS[$image_version_no_dot]})"
      else
        logerror "TEST_SUCCESS, TEST_SKIPPED and TEST_FAILED are all empty !"
      fi
    done

    if [ ${ci_nb_fail} -eq 0 ] && [ ${ci_nb_skipped} -eq 0 ]
    then
        ci="[![CI ok](https://img.shields.io/badge/$nb_success/$nb_tests-ok!-green)]($html_url)"
    elif [ ${ci_nb_fail} -eq ${nb_image_versions} ]
    then
        ci="[![CI fail](https://img.shields.io/badge/$nb_success/$nb_tests-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/$gh_issue_number)"
    fi
  fi

  if [ "$connector_path" != "" ]
  then
    version=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 3 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
    owner=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 5 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
    release_date=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 6 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
    documentation_url=$(grep "$connector_path " $tmp_dir/README.txt | cut -d "|" -f 7 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | sed 's/.*(\(.*\))/\1/')
    if [ "$release_date" = "null" ]
    then
      release_date="unknown"
    fi

    owner_badge=""
    if [ "$owner" != "" ]
    then
      if [[ "$owner" != *"Confluent"* ]]
      then
        ownerencoded=$(echo "$owner" | sed -e 's/ /%20/g')
        owner_badge="![owner](https://img.shields.io/badge/-$ownerencoded-blue)"
      fi
    fi
    
    versionencoded=$(urlencode $version)
    versionencoded=$(echo $versionencoded | tr "-" "_")
    release_date_encoded=$(urlencode $release_date)
    release_date_encoded=$(echo $release_date_encoded | tr "-" "_")
    connector_badge="[![version](https://img.shields.io/badge/v-$versionencoded%20($release_date_encoded)-pink)]($documentation_url)"

    # M1 Mac arm64 support
    arm64=""
    grep "${test}" ${root_folder}/scripts/arm64-support-with-emulation.txt > /dev/null
    if [ $? = 0 ]
    then
        arm64="![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange)"
    fi

    grep "${test}" ${root_folder}/scripts/arm64-support-none.txt > /dev/null
    if [ $? = 0 ]
    then
        arm64="![arm64](https://img.shields.io/badge/arm64-not%20working-red)"
    fi

    if [ "$arm64" == "" ]
    then
        arm64="![arm64](https://img.shields.io/badge/arm64-native%20support-green)"
    fi

    let "nb_connector_tests++"
    sed -e "s|:${test}:|\&nbsp; $connector_badge $owner_badge $arm64 $ci |g" \
        $content_file > $content_tmp_file

    cp $content_tmp_file $content_file
  else
    arm64=""
    grep "${test}" ${root_folder}/scripts/arm64-support-with-emulation.txt > /dev/null
    if [ $? = 0 ]
    then
        arm64="![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange)"
    fi

    grep "${test}" ${root_folder}/scripts/arm64-support-none.txt > /dev/null
    if [ $? = 0 ]
    then
        arm64="![arm64](https://img.shields.io/badge/arm64-not%20working-red)"
    fi

    if [ "$arm64" == "" ]
    then
        arm64="![arm64](https://img.shields.io/badge/arm64-native%20support-green)"
    fi

    sed -e "s|:${test}:|\&nbsp; $arm64 $ci |g" \
        $content_file > $content_tmp_file

    cp $content_tmp_file $content_file
  fi
done #end test_list

cp_version_tested=""
for image_version in $tags
do
  cp_version_tested="$cp_version_tested%20$image_version"
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
    $badges_file > $badges_tmp_file
cp $badges_tmp_file $badges_file

# Create docs/introduction.md
cat ./docs/introduction-header.md > ./docs/introduction.md
cat $badges_file >> ./docs/introduction.md
echo "" >> ./docs/introduction.md
cat ./docs/introduction-footer.md >> ./docs/introduction.md
