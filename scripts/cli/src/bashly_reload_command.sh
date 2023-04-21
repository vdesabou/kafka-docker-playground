DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

cd $root_folder/scripts/cli
bashly generate
rm -f $root_folder/scripts/cli/completions.bash
bashly add completions_script
cd - > /dev/null