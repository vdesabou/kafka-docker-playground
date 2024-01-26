# Using the standard library (lib/ini.sh) to show a value from the config
if [ ! -f "$root_folder/playground_config.ini" ]
then
    # set defaults
    playground config editor code > /dev/null 2>&1
    playground config clipboard true > /dev/null 2>&1
    playground config folder_zip_or_jar ~ > /dev/null 2>&1
fi
ini_load $root_folder/playground_config.ini

key="${args[key]:-}"
value=${ini[$key]:-}

if [[ "$value" ]]
then
  echo "$value"
else
  echo ""
fi