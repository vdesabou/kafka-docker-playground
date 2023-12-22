# Convert the space delimited string to an array
folders=''
eval "folders=(${args[folder]:-})"

folder_list=""
for i in "${folders[@]}"
do
    folder_list="$folder_list,$i"
done

log "📁 configuring folder_zip_or_jar with $folder_list"
playground config set folder_zip_or_jar "$folder_list"