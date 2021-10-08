
# 👨‍🏫 How to use

## 💻️ Running locally

* You just need to have [docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/) installed on your machine !

?> Every command used in the playground is using Docker, this includes `jq` (except if you have it on your host already), `aws`, `az`, `gcloud`, etc..
The goal is to have a consistent behaviour and only depends on Docker.

* 🐳 Recommended Docker settings:

![docker prefs](https://github.com/vdesabou/kafka-docker-playground/blob/4c3e6d481fcff7353a64e666d09f0921153a70e1/ccloud/ccloud-demo/images/docker-settings.jpg?raw=true)

## <img src="https://gitpod.io/static/media/gitpod.2cdd910d.svg" width="15"> Running using Gitpod

You can run the playground in your browser using [Gitpod.io](https://gitpod.io) workspace by clicking on this [link](https://gitpod.io/#https://github.com/vdesabou/kafka-docker-playground)

Look at awesome this is 🪄 !

![demo](https://github.com/vdesabou/gifs/raw/master/docs/images/gitpod.gif)

?> 50 hours/month can be used as part of the [free](https://www.gitpod.io/pricing) plan

You can login into Control Center (port `9021`) by clicking on `Open Browser` option in pop-up:

![port](./images/gitpod_port_popup.png)

Or select `Remote Explorer` on the left sidebar and then click on the `Open Browser` option corresponding to the port you want to connect to:

![port](./images/gitpod_port_explorer.png)

## 🌩 Running with AWS EC2 instance

If you want to run the playground on an EC2 instance, you can use the AWS CloudFormation template provided [here]([cloudformation/README.md](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.json)).

For example, this is how I start it using aws CLI:

```bash
$ cp kafka-docker-playground/cloudformation/kafka-docker-playground.json tmp.json
$ aws cloudformation create-stack  --stack-name kafka-docker-playground-$USER \
    --template-body file://tmp.json --region eu-west-3 \ 
    --parameters ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    ParameterKey=InstanceName,ParameterValue=kafka-docker-playground-$USER
```

## 
