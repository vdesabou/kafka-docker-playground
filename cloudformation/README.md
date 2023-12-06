# Using AWS CloudFormation

If you don't want to run the playground locally, you can run it easily on a EC2 instance

## Using AWS console

* Create stack in AWS CloudFormation and upload [this](https://raw.githubusercontent.com/vdesabou/kafka-docker-playground/master/cloudformation/alfred-aws-vscode-workflow/kafka-docker-playground.yml) template file:

![AWS CloudFormation](./Screenshot1.png)

* Fill information as requested (default EC2 instance type and root volume are recommended):

![AWS CloudFormation](./Screenshot2.png)

* After about 3 minutes, the stack will be created and you can see in *outputs* tab the public IP address of the EC2 instance:

![AWS CloudFormation](./Screenshot3.png)

## Using CLI:

For example, this is how I start it using aws CLI:

```bash
$ cp kafka-docker-playground/cloudformation/alfred-aws-vscode-workflow/kafka-docker-playground.yml tmp.yml
$ aws cloudformation create-stack  --stack-name kafka-docker-playground-$USER \
    --template-body file://tmp.yml --region eu-west-3 \ 
    --parameters ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    ParameterKey=InstanceName,ParameterValue=kafka-docker-playground-$USER \
    ParameterKey=LinuxUserName,ParameterValue="$USER"
```

## Using AWS EC2 Alfred workflow

See [here](https://kafka-docker-playground.io/#/how-to-use?id=🎩-aws-ec2-alfred-workflow) for all details.
