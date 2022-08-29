#!/bin/bash

lcc="$1"

if [[ "$lcc" == lcc-* ]]
then
    open "https://prd.logs.aws.confluent.cloud/_dashboards/app/discover#/?_g=(filters:!(),refreshInterval:(pause:!t,value:0),time:(from:now-30d,to:now))&_a=(columns:!(timestamp,message,level,exception.message,exception.stacktrace,logger),filters:!(('':(store:appState),meta:(alias:!n,disabled:!f,index:'90254960-dcdc-11ea-b484-556ef92a2241',key:mdc.connector.context,negate:!f,params:!('%5B$lcc%7Ctask-0%5D%20','%5B$lcc%7Cworker%5D%20','%5B$lcc%7Ctask-0%7CredoLog%5D%20'),type:phrases,value:'%5B$lcc%7Ctask-0%5D%20,%20%5B$lcc%7Cworker%5D%20,%20%5B$lcc%7Ctask-0%7CredoLog%5D%20'),query:(bool:(minimum_should_match:1,should:!((match_phrase:(mdc.connector.context:'%5B$lcc%7Ctask-0%5D%20')),(match_phrase:(mdc.connector.context:'%5B$lcc%7Cworker%5D%20')),(match_phrase:(mdc.connector.context:'%5B$lcc%7Ctask-0%7CredoLog%5D%20'))))))),index:'90254960-dcdc-11ea-b484-556ef92a2241',interval:auto,query:(language:lucene,query:''),sort:!(!('@timestamp',desc)))"
else
    echo "⚠️ Please set lcc-id"
    echo "lcc connector id is not set!"
    echo "Usage: open-lcc-logs.sh <lcc id>"
    exit 1
fi