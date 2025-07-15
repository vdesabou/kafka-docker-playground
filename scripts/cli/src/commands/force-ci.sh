filename="${args[filename]}"
all="${args[--all]}"
force="${args[--force]}"

if [[ -n "$all" ]]
then
    log "removing all ci files in s3://kafka-docker-playground/ci/"
    check_if_continue
    aws s3 rm --only-show-errors s3://kafka-docker-playground/ci/ --recursive --region us-east-1
    exit 0
fi


if [[ -n "$force" ]]
then
    GITHUB_RUN_NUMBER=1
fi

if [[ -n "$filename" ]]
then
    log "checking if file exists in s3://kafka-docker-playground/ci/ containing '$filename' in its name"
    files=$(aws s3 ls s3://kafka-docker-playground/ci/ --region us-east-1 | grep "$filename" | awk '{print $4}')

    if [[ -n "$files" ]]; then
        log "file(s) found: $files. Deleting..."
        for file in $files
        do
            log "deleting $file"
            check_if_continue
            aws s3 rm "s3://kafka-docker-playground/ci/$file" --only-show-errors --region us-east-1
        done
        log "file(s) deleted successfully."
    else
        log "no file found containing '$filename' in its name."
    fi
fi