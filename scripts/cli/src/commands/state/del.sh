# Using the standard library (lib/ini.sh) to delete a value from the config
if [ ! -f "$root_folder/playground.ini" ]
then
  touch $root_folder/playground.ini
fi
set -e
ini_load $root_folder/playground.ini

key="${args[key]}"
unset "ini[$key]"

ini_save $root_folder/playground.ini
