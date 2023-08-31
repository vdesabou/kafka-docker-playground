all="${args[--all]}"

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

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
    if git rev-parse --git-dir > /dev/null 2>&1
    then
        new_files=$(git status --porcelain 2>/dev/null  | grep "^?? " | cut -d " " -f2-)
        if [[ -n "$new_files" ]]
        then
            log "💫 detected new files:"
            echo "$new_files"
            tar cvfz "$output_filename" $new_files > /dev/null 2>&1
            if [ -f $final_archive ]
            then
                log "✅ Exported archive is available: $final_archive"
            else
                logerror "❌ export failed as archive could not be created !"
                exit 1
            fi
        else
            logerror "❌ No new files found !"
            exit 1
        fi
    else
        logerror "❌ output folder is not managed by git, please clone repository using git clone"
        exit 1
    fi
else
    # copy only current example
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

    test_file_directory="$(dirname "${test_file}")"
    base1="${test_file_directory##*/}" # connect-connect-aws-s3-sink
    dir1="${test_file_directory%/*}" # reproduction-models
    dir2="${dir1##*/}/$base1" # reproduction-models/connect-connect-aws-s3-sink

    if [[ "$dir2" != ${output_folder}* ]]
    then
        logerror "example <$dir2> is not from OUTPUT_FOLDER ${output_folder} folder, only examples in there can be exported"
        exit 1
    fi

    if git rev-parse --git-dir > /dev/null 2>&1
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
                log "✅ Exported archive is available: $final_archive"
            else
                logerror "❌ export failed as archive could not be created !"
                exit 1
            fi
        else
            logerror "❌ No new files found !"
            exit 1
        fi
    else
        logerror "❌ output folder is not managed by git, please clone repository using git clone"
        exit 1
    fi
fi
