
# 🎓 How to use

## 0️⃣ Prerequisites

You just need to have [docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/) installed on your machine !
Every command used in the playground is using Docker, this includes `jq` (except if you have it on your host already), `aws`, `az`, `gcloud`, etc..
The goal is to have a consistent behaviour and only depends on Docker.

## 🐳 Recommended Docker settings

![Diagram](https://github.com/vdesabou/kafka-docker-playground/blob/4c3e6d481fcff7353a64e666d09f0921153a70e1/ccloud/ccloud-demo/images/docker-settings.jpg?raw=true)

## 🌩 Running on AWS EC2 instance

If you want to run it on EC2 instance (highly recommended if you have low internet bandwith), you can use the AWS CloudFormation template provided [here]([cloudformation/README.md](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.json)).

For example, this is how I start it using aws CLI:

```bash
$ cp /path/to/kafka-docker-playground/cloudformation/kafka-docker-playground.json tmp.json
$ aws cloudformation create-stack  --stack-name kafka-docker-playground-$USER --template-body file://tmp.json --region eu-west-3
 --parameters ParameterKey=KeyName,ParameterValue=$KEY_NAME ParameterKey=InstanceName,ParameterValue=kafka-docker-playground-$USER
```

## <img src="https://gitpod.io/static/media/gitpod.2cdd910d.svg" width="15"> Running on Gitpod

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/vdesabou/kafka-docker-playground)
