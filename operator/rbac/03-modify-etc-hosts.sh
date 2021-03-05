#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

set +e
aws route53 list-hosted-zones-by-name --output text --dns-name "${domain}."  | grep "$domain" | grep "HOSTEDZONES"
if [[ $? != 0 ]]; then
    logerror "Hosted zone for domain $domain could not be found"
    exit 1
fi
set -e

hosted_zone_id=$(aws route53 list-hosted-zones-by-name --output json --dns-name "${domain}." | jq -r '.HostedZones[0].Id')

oldIFS="$IFS"
IFS=$'\n'
counter=0
for arecord in $(aws route53 list-resource-record-sets --hosted-zone-id ${hosted_zone_id} --output text --query "ResourceRecordSets[?Type == 'A'].[Name, AliasTarget.DNSName]")
do
  log "A record: $arecord"
  ((counter=counter+1))
done

if [ "$counter" != "4" ]
then
  logerror "The 4 DNS A records for domain ${domain} could not be found in Route53 Hosted Zone"
  logerror "Please retry in a few minutes or troubleshoot"
  exit 1
fi

for arecord in $(aws route53 list-resource-record-sets --hosted-zone-id ${hosted_zone_id} --output text --query "ResourceRecordSets[?Type == 'A'].[Name, AliasTarget.DNSName]")
do
  domain_host=$(echo "${arecord}" | awk '{print $1;}' | sed 's/.$//')
  dns=$(echo "${arecord}" | awk '{print $2;}' | sed 's/.$//')
  ip=$(dig +short $dns | tail -1)
  if [ "$ip" = "" ]
  then
    logerror "ip address for ${arecord} could not be found"
    exit 1
  fi
  log "Adding $ip $domain_host to your /etc/hosts (password can be asked)"
  removehost "$domain_host"
  addhost "$ip" "$domain_host"
  ((counter=counter+1))
done
IFS="$oldIFS"

