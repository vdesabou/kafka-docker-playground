#!/bin/ksh

query=$1

ip=$(echo $query | cut -d "|" -f 1)
name=$(echo $query | cut -d "|" -f 2)
id=$(echo $query | cut -d "|" -f 3)
state=$(echo $query | cut -d "|" -f 4)

group=$($aws_cli ec2 describe-instances --instance-id $id --output=json | /usr/local/bin/jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | /usr/local/bin/jq -r '.SecurityGroups[0] | .GroupName')

# delete all rules
$aws_cli ec2 revoke-security-group-ingress --group-name $group \
  --ip-permissions \
  "`aws ec2 describe-security-groups --output json --group-name $group --query "SecurityGroups[0].IpPermissions"`"

IP=`curl -s http://whatismyip.akamai.com/`
$aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 22   --cidr $IP/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 9021 --cidr $IP/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 9090 --cidr $IP/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8083 --cidr $IP/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3000 --cidr $IP/32 > /dev/null 2>&1 &

# # egress IPs for my AWS cluster playground:
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 13.36.97.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 13.36.104.9/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 13.36.132.239/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 13.37.18.182/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 15.188.179.40/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 15.236.107.72/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 15.236.121.33/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 15.236.192.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 35.180.176.16/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 35.181.12.7/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 35.181.19.147/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1414 --cidr 35.181.144.237/32 > /dev/null 2>&1 &

# # egress IPs for my AWS cluster playground:
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 13.36.97.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 13.36.104.9/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 13.36.132.239/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 13.37.18.182/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 15.188.179.40/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 15.236.107.72/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 15.236.121.33/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 15.236.192.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 35.180.176.16/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 35.181.12.7/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 35.181.19.147/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 8080 --cidr 35.181.144.237/32 > /dev/null 2>&1 &

# # egress ip cluster cdc oracle
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 13.36.97.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 13.36.104.9/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 13.36.132.239/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 13.37.18.182/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 15.188.179.40/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 15.236.107.72/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 15.236.121.33/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 15.236.192.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 35.180.176.16/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 35.181.12.7/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 35.181.19.147/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1521 --cidr 35.181.144.237/32 > /dev/null 2>&1 &


# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 13.36.97.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 13.36.104.9/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 13.36.132.239/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 13.37.18.182/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 15.188.179.40/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 15.236.107.72/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 15.236.121.33/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 15.236.192.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 35.180.176.16/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 35.181.12.7/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 35.181.19.147/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 3306 --cidr 35.181.144.237/32 > /dev/null 2>&1 &

# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 13.36.97.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 13.36.104.9/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 13.36.132.239/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 13.37.18.182/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 15.188.179.40/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 15.236.107.72/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 15.236.121.33/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 15.236.192.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 35.180.176.16/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 35.181.12.7/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 35.181.19.147/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 5672 --cidr 35.181.144.237/32 > /dev/null 2>&1 &

# # egress IPs for my AWS cluster playground:
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 13.36.97.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 13.36.104.9/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 13.36.132.239/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 13.37.18.182/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 15.188.179.40/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 15.236.107.72/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 15.236.121.33/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 15.236.192.85/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 35.180.176.16/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 35.181.12.7/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 35.181.19.147/32 > /dev/null 2>&1 &
# $aws_cli ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 1883 --cidr 35.181.144.237/32 > /dev/null 2>&1 &

if [ "$state" = "stopped" ]
then
	$aws_cli ec2 start-instances --instance-ids "$id"
	sleep 15
	ip=$($aws_cli ec2 describe-instances --instance-ids "$id" | /usr/local/bin/jq ".Reservations[0].Instances[0].PublicDnsName" | tr -d '"')
fi

mkdir -p $HOME/.ssh
SSH_CONFIG_FILE=$HOME/.ssh/config

username=$(whoami)

grep "$name" $SSH_CONFIG_FILE > /dev/null
if [ $? = 0 ]
then
    OLDIP=`grep -w $name -A 1 ${SSH_CONFIG_FILE} | awk '/HostName/ {print $2}'`
    sed -e "s/$OLDIP/$ip/g" ${SSH_CONFIG_FILE} > /tmp/tmp_file
    mv /tmp/tmp_file ${SSH_CONFIG_FILE}
else
cat << EOF >> ${SSH_CONFIG_FILE}

Host $name
  HostName $ip
  IdentityFile $ssh_pem_file
  User $username
  StrictHostKeyChecking no
EOF

fi

/usr/local/bin/code --folder-uri "vscode-remote://ssh-remote+$name/home/$username"
