all="${args[--all]}"

if [ ! -z "$OUTPUT_FOLDER" ]
then
  output_folder="$OUTPUT_FOLDER"
else
  output_folder="reproduction-models"
fi

if [ "$output_folder" != "reproduction-models" ]
then
    logerror "❌ OUTPUT_FOLDER $output_folder is not set with reproduction-models, this is the only supported value !"
    exit 1
fi

repro_dir=$root_folder/$output_folder
cd $repro_dir

output_filename="playground_repro_export.tgz"
final_archive=$repro_dir/$output_filename
if [ -f $final_archive ]
then
    rm -rf $final_archive
fi
set +e
if [[ -n "$all" ]]
then
    if [ -e .git ]
    then
        new_files=$(git status --porcelain 2>/dev/null  | grep "^?? " | cut -d " " -f2-)
        if [[ -n "$new_files" ]]
        then
            log "💫 detected new files:"
            echo "$new_files"
            tar cvfz "$output_filename" $new_files > /dev/null 2>&1
            if [ -f $final_archive ]
            then
                log "📤 Exported archive is available: $final_archive"
            else
                logerror "❌ export failed as archive could not be created !"
                exit 1
            fi
        else
            logerror "❌ No new files found !"
            exit 1
        fi
    else
        logwarn "output folder is not managed by git, creating a full tgz of $output_folder"
        tar cvfz "$output_filename" * > /dev/null 2>&1
        if [ -f $final_archive ]
        then
            log "📤 Exported archive is available: $final_archive"
        else
            logerror "❌ export failed as archive could not be created !"
            exit 1
        fi
    fi
else
    # copy only current example
    test_file=$(playground state get run.test_file)

    if [ ! -f $test_file ]
    then 
        logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
        exit 1
    fi

    test_file_directory="$(dirname "${test_file}")"
    base1="${test_file_directory##*/}" # connect-connect-aws-s3-sink
    dir1="${test_file_directory%/*}" # reproduction-models
    dir2="${dir1##*/}/$base1" # reproduction-models/connect-connect-aws-s3-sink

    if [[ "$dir2" != ${output_folder}* ]]
    then
        logerror "example <$dir2> is not from OUTPUT_FOLDER ${output_folder} folder, only examples in there can be exported"
        exit 1
    fi

    if [ -e .git ]
    then
        cd $test_file_directory

        new_files=$(git status --porcelain . 2>/dev/null  | grep "^?? " | cut -d " " -f2-)
        if [[ -n "$new_files" ]]
        then
            log "💫 detected new files:"
            echo "$new_files"
            cd - >/dev/null
            tar cvfz "$output_filename" $new_files > /dev/null 2>&1
            if [ -f $final_archive ]
            then
                log "📤 Exported archive is available: $final_archive"
            else
                logerror "❌ export failed as archive could not be created !"
                exit 1
            fi
        else
            logerror "❌ No new files found !"
            exit 1
        fi
    else
        logwarn "output folder is not managed by git, creating a full tgz of $test_file_directory"
        tar cvfz "$output_filename" $test_file_directory > /dev/null 2>&1
        if [ -f $final_archive ]
        then
            log "📤 Exported archive is available: $final_archive"
        else
            logerror "❌ export failed as archive could not be created !"
            exit 1
        fi
    fi
fi
