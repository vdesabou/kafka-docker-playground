#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

TMP_DIR=/tmp/asciinema
rm -rf $TMP_DIR/
mkdir -p $TMP_DIR

# go to root folder
cd ${DIR}/..

test_list="$1"
if [ "$1" = "ALL" ]
then
    test_list="connect/* environment/* replicator/* other/* kafka-tutorials/kafka-streams/* kafka-tutorials/ksql/*"
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

        if [ -f asciinema.gif ]
        then
            logwarn "####################################################"
            logwarn "asciinema.gif already exists, skipping dir $dir"
            logwarn "####################################################"
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

        if [ -d $TMP_DIR/$dir ]
        then
            # we want to execute only one script
            break
        fi

        mkdir -p $TMP_DIR/$dir

        log "####################################################"
        log "Executing $script in dir $dir"
        log "####################################################"

        ####
        ##
        sed -e "s|MYDIR|$dir|g" \
            -e "s|MYSCRIPT|$script|g" \
            ${DIR}/asciinema-script-template.yml > /tmp/asciinema-script.yml

        spielbash -v record --script=/tmp/asciinema-script.yml --output=$TMP_DIR/$dir/asciinema.cast
        sleep 1
        bash stop.sh
        asciicast2gif -w 80 $TMP_DIR/$dir/asciinema.cast $PWD/asciinema.gif
    done
    cd - > /dev/null
done