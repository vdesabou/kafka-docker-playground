#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/../connect
echo $PWD
for dir in $(ls -d *)
do
    if [ ! -d $dir ]
    then
        continue
    fi

    # check for ignored folders in scripts/tests-ignored.txt
    grep "$dir" ${DIR}/tests-ignored.txt > /dev/null
    if [ $? = 0 ]
    then
        log "####################################################"
        log "skipping $dir"
        log "####################################################"
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

        #filename="${script%.*}"
        ####
        ##
        log "####################################################"
        log "Executing $script in dir $dir"
        log "####################################################"
        bash $script
        bash stop.sh
    done
    cd - > /dev/null
done