test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

test_file_directory="$(dirname "${test_file}")"
base1="${test_file_directory##*/}" # connect-cdc-oracle12-source
dir1="${test_file_directory%/*}" #connect
dir2="${dir1##*/}/$base1" # connect/connect-cdc-oracle12-source

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

content_file="$tmp_dir/content.md"
curl -s -o $content_file  https://raw.githubusercontent.com/vdesabou/kafka-docker-playground-docs/main/docs/content.md

result_ok="$(grep "$dir2" $content_file | sed -n 's/.*\[CI \(ok\)\].*(\(https[^)]*\)).*/🤖CI status: 🟢 ok\n🔗test url: \2/p')"
result_fail="$(grep "$dir2" $content_file | sed -n 's/.*\[CI \(fail\)\].*(\(https[^)]*\)).*/🤖CI status: 🔴 fail\n🐛 github issue: \2/p')"
result_not_tested="$(grep "$dir2" $content_file | sed -n 's/.*\[not tested\].*/🤖CI status: 🤷‍♂️ not tested/p')"

# print only result not empty
if [ -n "$result_ok" ]; then
    log "$result_ok"
fi

if [ -n "$result_fail" ]; then
    logwarn "$result_fail"
fi

if [ -n "$result_not_tested" ]; then
    log "$result_not_tested"
fi