# Using the standard library (lib/ini.sh) to show the entire config file
if [ ! -f $root_folder/playground.ini ]
then
    touch $root_folder/playground.ini
fi
ini_load $root_folder/playground.ini
ini_show