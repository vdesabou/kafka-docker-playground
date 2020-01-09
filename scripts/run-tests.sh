#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

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
        echo "skipping $dir"
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
            echo "skipping $script in dir $dir"
            continue
        fi

        #filename="${script%.*}"
        ####
        ##
        echo "Executing $script in dir $dir"
        bash $script
        bash stop.sh
    done
    cd - > /dev/null
done