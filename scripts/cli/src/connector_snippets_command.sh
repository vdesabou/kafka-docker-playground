converter=${args[converter]}
dlq=${args[--dlq]}

environment=$(playground state get run.environment_before_switch)
if [ "$environment" = "" ]
then
    environment=$(playground state get run.environment)
fi

if [ "$environment" = "" ]
then
    environment="plaintext"
fi

