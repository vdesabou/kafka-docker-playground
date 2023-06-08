#!/bin/sh

file=/tmp/out.json
rm -rf $file
for (( i=1; i <= $NB_MESSAGES; ++i ))
do
    rm -rf /tmp/mock
    node /usr/local/bin/mock-pb g -o /tmp/mock > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        echo "mock-pb failed to produce protobuf "
        cat /tmp/result.log
        exit 1
    fi
    find /tmp/mock/ -type f -name "*.json" -exec cat {} + >> $file
done

cat $file