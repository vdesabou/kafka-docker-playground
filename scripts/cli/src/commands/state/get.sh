# Using the standard library (lib/ini.sh) to show a value from the config
if [ ! -f "$root_folder/playground.ini" ]
then
  touch $root_folder/playground.ini
fi
ini_load $root_folder/playground.ini

key="${args[key]:-}"
value=${ini[$key]:-}

if [[ "$value" ]]
then
  echo "$value"
else
  echo ""
fi