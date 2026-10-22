#!/bin/sh

# mock-pb maps 32-bit integer types to mockjs @integer / @natural without a range (values up to 2^53),
# and 64-bit ones to strings of up to 20 digits: protobuf rejects both, keep them in range
mock_js="$(npm root -g 2>/dev/null)/mock-pb-cli/bin/libs/mock.js"
if [ -f "$mock_js" ]
then
    sed -i -E \
        -e "s/^( +(int32|sint32|sfixed32): )'@integer',/\1'@integer(-2147483648, 2147483647)',/" \
        -e "s/^( +(uint32|fixed32): )'@natural',/\1'@natural(0, 4294967295)',/" \
        -e "s/^( +(int64|uint64|sint64|fixed64|sfixed64): )'@string\(\"1234567890\", 1, 20\)',/\1'@string(\"1234567890\", 1, 18)',/" \
        "$mock_js"
fi

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