container="${args[--container]}"
restore_original_values="${args[--restore-original-values]}"

# Convert the space delimited string to an array
eval "env_array=(${args[--env]})"

if [[ ! -n "$restore_original_values" ]]
then
    # check if ebv_arrya is empty
    if [ ${#env_array[@]} -eq 0 ]
    then
        logerror "❌ No environment variables provided with --env option"
        exit 1
    fi
fi

# For ccloud case
if [ -f $root_folder/.ccloud/env.delta ]
then
     source $root_folder/.ccloud/env.delta
fi

# keep TAG, CONNECT TAG and ORACLE_IMAGE
export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

docker_command=$(playground state get run.docker_command)
if [ "$docker_command" == "" ]
then
  logerror "docker_command retrieved from $root_folder/playground.ini is empty !"
  exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if [[ ! -n "$restore_original_values" ]]
then
    cat << EOF > $tmp_dir/docker-compose.override.java.env.yml
services:
  $container:
    environment:
      DUMMY: $RANDOM
EOF


    for env_variable in "${env_array[@]}"
    do
    env_list="$env_list $env_variable"
    cat << EOF >> $tmp_dir/docker-compose.override.java.env.yml
      $env_variable
EOF

    done

    log "📦 enabling container $container with environment variables $env_list"
    echo "$docker_command" > $tmp_dir/playground-command-java-env
    sed -i -E -e "s|up -d --quiet-pull|-f $tmp_dir/docker-compose.override.java.env.yml up -d --quiet-pull|g" $tmp_dir/playground-command-java-env
    load_env_variables
    bash $tmp_dir/playground-command-java-env
else
    log "🧽 restore back original values before any changes was made for container $container"
    echo "$docker_command" > $tmp_dir/playground-command
    load_env_variables
    bash $tmp_dir/playground-command
fi