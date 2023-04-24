if [ ! -f /tmp/playground-run ]
then
  logerror "File containing re-run command /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

test_file=$(cat /tmp/playground-run | awk '{ print $4}')

if [ ! -f $test_file ]
then 
  logerror "File $test_file retrieved from /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

if [ ! -z $EDITOR ]
then
    log "📖 Opening ${test_file} using EDITOR environment variable"
    $EDITOR ${test_file}
else
    if [[ $(type code 2>&1) =~ "not found" ]]
    then
        logerror "Could not determine an editor to use, you can set EDITOR environment variable with your preferred choice"
        exit 1
    else
        log "📖 Opening ${test_file} with code (you can change editor by setting EDITOR environment variable)"
        code ${test_file}
    fi
fi