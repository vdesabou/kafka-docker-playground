cd $root_folder/scripts/cli
bashly generate
rm -f $root_folder/scripts/cli/completions.bash
bashly add completions_script
cd - > /dev/null