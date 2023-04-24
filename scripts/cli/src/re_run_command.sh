if [ ! -f /tmp/playground-run ]
then
  logerror "File containing re-run command /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

log "Run command again:"
cat /tmp/playground-run
bash /tmp/playground-run