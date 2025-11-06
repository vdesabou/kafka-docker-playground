containers="${args[--container]}"
restore_original_values="${args[--restore-original-values]}"
mount_jscissors_files="${args[--mount-jscissors-files]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

# Convert the space delimited string to an array
eval "env_array=(${args[--env]})"

if [[ ! -n "$restore_original_values" ]]
then
    # check if env_array is empty
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
export CP_CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
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
EOF

    # Generate environment variables for each container
    for container in "${container_array[@]}"
    do
        cat << EOF >> $tmp_dir/docker-compose.override.java.env.yml
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

        if [[ -n "$mount_jscissors_files" ]]
        then
            cat << EOF >> $tmp_dir/docker-compose.override.java.env.yml
    volumes:
      - ${root_folder}/scripts/cli/src/jscissors/jscissors-1.0-SNAPSHOT.jar:/tmp/jscissors-1.0-SNAPSHOT.jar
      - /tmp/:/tmp/
EOF
        fi
    done

    log "📦 enabling containers ${containers} with environment variables $env_list"
    echo "$docker_command" > $tmp_dir/playground-command-java-env
    sed -i -E -e "s|up -d --quiet-pull|-f $tmp_dir/docker-compose.override.java.env.yml up -d --quiet-pull|g" $tmp_dir/playground-command-java-env
    load_env_variables
    bash $tmp_dir/playground-command-java-env
else
    log "🧽 restore back original values before any changes was made for containers ${containers}"
    echo "$docker_command" > $tmp_dir/playground-command
    load_env_variables
    bash $tmp_dir/playground-command
fi
wait_container_ready


test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

if [[ "${test_file}" == *"xstream"* ]]
then
    log "💫 xstream test detected, re-installing libraries..."
    # https://github.com/confluentinc/common-docker/pull/743 and https://github.com/adoptium/adoptium-support/issues/1285
    set +e
    playground container exec --root --command "sed -i "s/packages\.adoptium\.net/adoptium\.jfrog\.io/g" /etc/yum.repos.d/adoptium.repo"
    playground container exec --root --command "microdnf -y install libaio"

    if [ "$(uname -m)" = "arm64" ]
    then
        :
    else
        if version_gt $TAG_BASE "7.9.9"
        then
            playground container exec --root --command "microdnf -y install libnsl2"
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.3 /usr/lib64/libnsl.so.1"
        else
            playground container exec --root --command "ln -s /usr/lib64/libnsl.so.2 /usr/lib64/libnsl.so.1"
        fi
    fi
fi