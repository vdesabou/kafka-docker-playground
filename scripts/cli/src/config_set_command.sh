# Using the standard library (lib/ini.sh) to store a value to the config
if [ ! -f $root_folder/playground_config.ini ]
then
    touch $root_folder/playground_config.ini
fi
set -e
ini_load $root_folder/playground_config.ini

key="${args[key]}"
value="${args[value]}"

ini["$key"]="$value"
ini_save $root_folder/playground_config.ini