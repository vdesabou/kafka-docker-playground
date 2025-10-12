tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

curl -H "Authorization: Token $GH_TOKEN" -s "https://raw.githubusercontent.com/confluentinc/cc-docker-connect/refs/heads/master/cc-connect/cache-versions.env" -o $tmp_dir/cache-versions.env

if [ ! -f $tmp_dir/cache-versions.env ]
then
    logerror "❌ could not download cache-versions.env"
    exit 1
fi

aws s3 cp --only-show-errors $tmp_dir/cache-versions.env s3://kafka-docker-playground/3rdparty/cache-versions.env
if [ $? -ne 0 ]
then
    logerror "❌ could not upload cache-versions.env to s3://kafka-docker-playground/3rdparty/cache-versions.env"
    exit 1
fi