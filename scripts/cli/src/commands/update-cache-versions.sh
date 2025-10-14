curl -H "Authorization: Token $GH_TOKEN" -s "https://raw.githubusercontent.com/confluentinc/cc-docker-connect/refs/heads/master/cc-connect/cache-versions.env" -o /tmp/cache-versions.env

if [ ! -f /tmp/cache-versions.env ]
then
    logerror "❌ could not download cache-versions.env"
    exit 1
fi

aws s3 cp --only-show-errors /tmp/cache-versions.env s3://kafka-docker-playground/3rdparty/cache-versions.env
if [ $? -ne 0 ]
then
    logerror "❌ could not upload cache-versions.env to s3://kafka-docker-playground/3rdparty/cache-versions.env"
    exit 1
fi