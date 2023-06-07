#!/bin/sh

file=/tmp/out.json
rm -rf $file
for (( i=1; i <= $NB_MESSAGES; ++i ))
do
    rm -rf /tmp/mock
    node /usr/local/bin/mock-pb g -o /tmp/mock > /dev/null 2>&1
    cat /tmp/mock/*.json >> $file
done

cat $file