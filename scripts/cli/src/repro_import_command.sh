file="${args[--file]}"

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

if [[ $file == *"@"* ]]
then
  file=$(echo "$file" | cut -d "@" -f 2)
fi

filename=$(basename $file)

if [ "playground_repro_export.tgz" != ${filename} ]
then
    logerror "file $file is not named playground_repro_export.tgz"
    exit 1
fi

repro_dir=$root_folder/$output_folder
cd $repro_dir

log "📥 Installing $file"
tar xvfz $file