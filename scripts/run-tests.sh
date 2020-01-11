#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

# go to root folder
cd ${DIR}/..

nb_test_failed=0
failed_tests=""

for dir in $@
do
    if [ ! -d $dir ]
    then
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
            log "####################################################"
            log "skipping $script in dir $dir"
            log "####################################################"
            continue
        fi

        log "####################################################"
        log "Executing $script in dir $dir"
        log "####################################################"
        bash $script
        ecd
        if [ $? -eq 0 ]
        then
            log "####################################################"
            log "RESULT: SUCCESS for $script in dir $dir"
            log "####################################################"
        else
            log "####################################################"
            log "RESULT: FAILURE for $script in dir $dir"
            log "####################################################"
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
    log "####################################################"
    log "RESULT: FAILED $nb_test_failed tests failed:\n $failed_tests"
    log "####################################################"
    exit $nb_test_failed
fi