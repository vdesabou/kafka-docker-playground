#!/bin/bash
# creates the bore server of the playground tunnels in AWS (see README.md): a t4g.nano running Amazon Linux 2023 (arm64)
# with server-user-data.sh, a security group open on 7835 (bore control port) and 40000-40999 (tunnels), and an Elastic IP.
# The secret is generated in ~/.kdp-bore/secret (never printed); BORE_SERVER is printed at the end.
#
# The tunnel ports only receive the connections of the fully managed connectors (the bore clients, on the runners, only
# use 7835): list the egress IPs of your Confluent Cloud clusters in ~/.kdp-bore/allowed-cidrs.txt, one CIDR per line,
# to only open 40000-40999 to them. Without that file, the tunnel ports are open to everyone.
#
#   AWS_PROFILE=<profile> tools/bore-tunnel/create-server.sh [region]       (default region: eu-west-3)
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
export AWS_REGION="${1:-eu-west-3}"
NAME="kdp-bore-server"
TAGS="{Key=Name,Value=$NAME},{Key=owner,Value=${USER}},{Key=purpose,Value=kafka-docker-playground-tunnels},{Key=cflt_managed_by,Value=user},{Key=cflt_managed_id,Value=${USER}}"

if aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text | grep -q .
then
    echo "❌ an instance named $NAME already exists in $AWS_REGION" >&2
    exit 1
fi

umask 077
mkdir -p "$HOME/.kdp-bore"
if [ ! -s "$HOME/.kdp-bore/secret" ]
then
    openssl rand -hex 32 > "$HOME/.kdp-bore/secret"
fi

ami=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 --query Parameter.Value --output text)
vpc=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)

sg=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$NAME" "Name=vpc-id,Values=$vpc" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$sg" == "None" ]
then
    sg=$(aws ec2 create-security-group --group-name "$NAME" --description "bore tunnel server for kafka-docker-playground" --vpc-id "$vpc" \
        --tag-specifications "ResourceType=security-group,Tags=[$TAGS]" --query GroupId --output text)
    # the bore clients run on GitHub runners and laptops, whose IPs are unknown: the control port is open, the secret protects it
    aws ec2 authorize-security-group-ingress --group-id "$sg" --ip-permissions \
        'IpProtocol=tcp,FromPort=7835,ToPort=7835,IpRanges=[{CidrIp=0.0.0.0/0,Description=bore control port}]' > /dev/null
    cidrs=()
    if [ -f "$HOME/.kdp-bore/allowed-cidrs.txt" ]
    then
        while read -r cidr
        do
            [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] && cidrs+=("$cidr")
        done < <(sed 's/#.*//; s/[^0-9./]//g' "$HOME/.kdp-bore/allowed-cidrs.txt")
    fi
    if [ ${#cidrs[@]} -eq 0 ]
    then
        cidrs=("0.0.0.0/0")
        echo "⚠️ no ~/.kdp-bore/allowed-cidrs.txt: the tunnel ports are open to everyone"
    fi
    ranges=$(printf '{CidrIp=%s,Description=bore tunnels},' "${cidrs[@]}")
    aws ec2 authorize-security-group-ingress --group-id "$sg" --ip-permissions \
        "IpProtocol=tcp,FromPort=40000,ToPort=40999,IpRanges=[${ranges%,}]" > /dev/null
    echo "🔒 tunnel ports 40000-40999 open to ${#cidrs[@]} CIDR(s)"
fi
echo "🛡️ security group $sg"

user_data=$(mktemp)
trap 'rm -f "$user_data"' EXIT
sed "s/__BORE_SECRET__/$(cat "$HOME/.kdp-bore/secret")/" "$DIR/server-user-data.sh" > "$user_data"

instance=$(aws ec2 run-instances --image-id "$ami" --instance-type t4g.nano --count 1 --security-group-ids "$sg" \
    --user-data "file://$user_data" --metadata-options HttpTokens=required,HttpEndpoint=enabled \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}' \
    --tag-specifications "ResourceType=instance,Tags=[$TAGS]" "ResourceType=volume,Tags=[$TAGS]" \
    --query 'Instances[0].InstanceId' --output text)
echo "🖥️ instance $instance"
aws ec2 wait instance-running --instance-ids "$instance"

allocation=$(aws ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[$TAGS]" --query AllocationId --output text)
aws ec2 associate-address --instance-id "$instance" --allocation-id "$allocation" > /dev/null
host=$(aws ec2 describe-addresses --allocation-ids "$allocation" --query 'Addresses[0].PublicIp' --output text)
echo "$host" > "$HOME/.kdp-bore/server"

echo "✅ bore server starting on $host (about a minute for the user data to install bore)"
echo "   export BORE_SERVER=$host"
echo "   export BORE_SECRET=\$(cat ~/.kdp-bore/secret)"
