topic="${args[--topic]}"


if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

log "Get number of records in a topic $topic"
if [ "$environment" != "plaintext" ]
then
    # see heredocs.sh
    get_number_records_topic_command_heredoc_with_security "$topic"
else
    # see heredocs.sh
    get_number_records_topic_command_heredoc "$topic"
fi