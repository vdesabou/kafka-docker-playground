get_environment_used
if [[ "$environment" == cfk* ]]
then
  logerror "❌ get-docker-compose is not supported in cfk mode: the components are pods, see them with 'kubectl -n confluent get pods'"
  exit 1
fi

docker_command=$(playground state get run.docker_command)
if [ "$docker_command" == "" ]
then
  logerror "❌ docker_command retrieved from $root_folder/playground.ini is empty, is an environment running? (playground status)"
  exit 1
fi

export IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

# keep the versions of the running containers (an empty tag would fall back to the default one of scripts/utils.sh)
broker_container="broker"
if [[ "$environment" == mdc* ]]
then
  broker_container="broker-us"
fi
running_tag=$(docker inspect -f '{{.Config.Image}}' "$broker_container" 2> /dev/null | cut -d ":" -f 2)
[[ -n "$running_tag" ]] && export TAG="$running_tag"
running_connect_tag=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
[[ -n "$running_connect_tag" ]] && export CP_CONNECT_TAG="$running_connect_tag"
running_oracle_image=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)
[[ -n "$running_oracle_image" ]] && export ORACLE_IMAGE="$running_oracle_image"

# only the path of the mounted file is needed to render the configuration: no AWS credentials required
export AWS_CREDENTIALS_FILE_NAME="/tmp/aws_credentials"

enable_flink=$(playground state get flags.ENABLE_FLINK)
if [ "$enable_flink" != "1" ]
then
  export flink_connectors=""
fi

if [[ "$environment" == "ccloud" ]]
then
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta
  if [ -f $DELTA_CONFIGS_ENV ]
  then
    source $DELTA_CONFIGS_ENV
  else
    logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
    exit 1
  fi
fi

tmp_command=$(mktemp -t playground-command-config.XXXXXX)
trap 'rm -f "$tmp_command"' EXIT
# 'docker compose config' instead of 'up -d', and the logs of scripts/utils.sh out of stdout, so that the output is
# valid YAML (playground get-docker-compose > docker-compose.yml)
echo "$docker_command" | sed -e "s|up -d|config|g" \
    -e "s|--quiet-pull||g" \
    -e "s|scripts/utils.sh &&|scripts/utils.sh > /dev/null \&\&|" > "$tmp_command"

bash "$tmp_command"
