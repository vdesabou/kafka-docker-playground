#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

# go to root folder
cd ${DIR}/..

nb_test_failed=0
failed_tests=""

test_list="$1"
if [ "$1" = "ALL" ]
then
    test_list=$(grep "env: TEST_LIST" ${DIR}/../.travis.yml | cut -d '"' -f 2 | tr '\n' ' ')
fi

tag="$2"
if [ "$tag" != "" ]
then
    export TAG=$tag
fi

for dir in $test_list
do
    if [ ! -d $dir ]
    then
        logwarn "####################################################"
        logwarn "skipping dir $dir, not a directory"
        logwarn "####################################################"
        continue
    fi

    cd $dir > /dev/null

    for script in *.sh
    do
        if [[ "$script" = "stop.sh" ]]
        then
            continue
        fi

        # check for ignored scripts in scripts/tests-ignored.txt
        grep "$script" ${DIR}/tests-ignored.txt > /dev/null
        if [ $? = 0 ]
        then
            logwarn "####################################################"
            logwarn "skipping $script in dir $dir"
            logwarn "####################################################"
            continue
        fi

        # check for scripts containing "repro"
        if [[ "$script" == *"repro"* ]]; then
            logwarn "####################################################"
            logwarn "skipping reproduction model $script in dir $dir"
            logwarn "####################################################"
            continue
        fi

        log "####################################################"
        log "Executing $script in dir $dir"
        log "####################################################"
        SECONDS=0
        retry bash $script
        ret=$?
        ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
        let ELAPSED_TOTAL+=$SECONDS
        CUMULATED="cumulated time: $((($ELAPSED_TOTAL / 60) % 60))min $(($ELAPSED_TOTAL % 60))sec"
        if [ $ret -eq 0 ]
        then
            log "####################################################"
            log "RESULT: SUCCESS for $script in dir $dir ($ELAPSED - $CUMULATED)"
            log "####################################################"
        else
            logerror "####################################################"
            logerror "RESULT: FAILURE for $script in dir $dir ($ELAPSED - $CUMULATED)"
            logerror "####################################################"
            failed_tests=$failed_tests"$dir[$script]\n"
            let "nb_test_failed++"
        fi
        bash stop.sh
    done
    cd - > /dev/null
done


if [ $nb_test_failed -eq 0 ]
then
    log "####################################################"
    log "RESULT: SUCCESS"
    log "####################################################"
    exit 0
else
    logerror "####################################################"
    logerror "RESULT: FAILED $nb_test_failed tests failed:\n$failed_tests"
    logerror "####################################################"
    exit $nb_test_failed
fi