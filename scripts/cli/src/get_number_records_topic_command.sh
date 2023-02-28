
topic="${args[--topic]}"

log "Get number of records in a topic $topic"
# see heredocs.sh
get_number_records_topic_command_heredoc "$topic"