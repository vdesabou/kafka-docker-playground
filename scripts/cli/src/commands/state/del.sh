# Using the standard library (lib/ini.sh) to delete a value from the config
if [ ! -f "$root_folder/playground.ini" ]
then
    logerror "$root_folder/playground.ini does not exist !"
    logerror "Make sure to always use the CLI to run examples"
    exit 1
fi
set -e
ini_load $root_folder/playground.ini

key="${args[key]}"
unset "ini[$key]"

ini_save $root_folder/playground.ini
