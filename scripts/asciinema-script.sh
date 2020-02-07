#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

TMP_DIR=/tmp/asciinema
rm -rf $TMP_DIR/
mkdir -p $TMP_DIR

# go to root folder
cd ${DIR}/..

OUT_FILE=${DIR}/../out.sh

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
            ${DIR}/asciinema-script-template.yml > $TMP_DIR/$dir/asciinema-script.yml

        echo "cd $dir;clear"  >> $OUT_FILE

        echo "asciinema rec $TMP_DIR/$dir/asciinema.cast --overwrite" >> $OUT_FILE
        echo "./$script"  >> $OUT_FILE
        #echo "spielbash -v record --script=$TMP_DIR/$dir/asciinema-script.yml --output=$TMP_DIR/$dir/asciinema.cast" >> $OUT_FILE
        #sleep 1
        #echo "bash stop.sh"  >> $OUT_FILE
        echo 'exit'  >> $OUT_FILE
        echo 'docker rm -f $(docker ps -a -q)'  >> $OUT_FILE
        echo "asciicast2gif -w 80 $TMP_DIR/$dir/asciinema.cast $PWD/asciinema.gif" >> $OUT_FILE
        echo "cd -"  >> $OUT_FILE
    done
    cd - > /dev/null
done