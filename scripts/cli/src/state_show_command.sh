# Using the standard library (lib/ini.sh) to show the entire config file
if [ ! -f "$root_folder/playground.ini" ]
then
    logerror "$root_folder/playground.ini does not exist !"
    logerror "Make sure to always use the CLI to run exampls"
    exit 1
fi
ini_load $root_folder/playground.ini
ini_show