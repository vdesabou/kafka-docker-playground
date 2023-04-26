if [ ! -f /tmp/playground-run ]
then
  logerror "File containing re-run command /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"
connector_jar="${args[--connector-jar]}"
disable_ksqldb="${args[--disable-ksqldb]}"
disable_c3="${args[--disable-control-center]}"
enable_conduktor="${args[--enable-conduktor]}"
enable_multiple_brokers="${args[--enable-multiple-brokers]}"
enable_multiple_connect_workers="${args[--enable-multiple-connect-workers]}"
enable_jmx_grafana="${args[--enable-jmx-grafana]}"
enable_kcat="${args[--enable-kcat]}"
enable_sr_maven_plugin_app="${args[--enable-sr-maven-plugin-app]}"
enable_sql_datagen="${args[--enable-sql-datagen]}"

flag_list=""
if [[ -n "$tag" ]]
then
  flag_list="--tag=$tag"
fi

if [[ -n "$connector_tag" ]]
then
  flag_list="$flag_list --connector-tag=$connector_tag"
fi

if [[ -n "$connector_zip" ]]
then
  if [[ $connector_zip == *"@"* ]]
  then
    connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-zip=$connector_zip"
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-jar=$connector_jar"
fi

if [[ -n "$disable_ksqldb" ]]
then
  flag_list="$flag_list --disable-ksqldb"
fi

if [[ -n "$disable_c3" ]]
then
  flag_list="$flag_list --disable-control-center"
fi

if [[ -n "$enable_conduktor" ]]
then
  flag_list="$flag_list --enable-conduktor"
fi

if [[ -n "$enable_multiple_brokers" ]]
then
  flag_list="$flag_list --enable-multiple-broker"
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  flag_list="$flag_list --enable-multiple-connect-workers"
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  flag_list="$flag_list --enable-jmx-grafana"
fi

if [[ -n "$enable_kcat" ]]
then
  flag_list="$flag_list --enable-kcat"
fi

if [[ -n "$enable_sr_maven_plugin_app" ]]
then
  flag_list="$flag_list --enable-sr-maven-plugin-app"
fi

if [[ -n "$enable_sql_datagen" ]]
then
  flag_list="$flag_list --enable-sql-datagen"
fi

if [ "$flag_list" != "" ]
then
  test_file=$(cat /tmp/playground-run | awk '{ print $4}')

  if [ ! -f $test_file ]
  then 
    logerror "File $test_file retrieved from /tmp/playground-run does not exist!"
    logerror "Make sure to use <playground run> command !"
    exit 1
  fi

  log "🚀 Running example again with new flags"
  log "⛳ Flags used are $flag_list"
  playground run -f $test_file $flag_list ${other_args[*]}
else
  log "🚀 Running example again with same flags as before"
  cat /tmp/playground-run
  bash /tmp/playground-run
fi