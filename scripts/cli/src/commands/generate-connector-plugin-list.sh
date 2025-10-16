tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

tmp_file=$tmp_dir/confluent-hub-plugin-list.txt
tmp_file2=$tmp_dir/allmanis.json

curl -s -S 'https://api.hub.confluent.io/api/plugins?per_page=100000' | jq '. | sort_by(.release_date) | reverse | .' > $tmp_file2
jq -r '.[] | "\(.owner.username)/\(.name)|\(.source_url)"' $tmp_file2 | grep -v "NA/" | sort | uniq > $tmp_file
rm -f $tmp_file2

# confluent only
cd $tmp_dir > /dev/null
get_3rdparty_file "confluent-plugin-sourcecode-mapping-list.txt" > /dev/null
cd - > /dev/null
if [ -f $tmp_dir/confluent-plugin-sourcecode-mapping-list.txt ]
then
    echo "# CONFLUENT EMPLOYEE VERSION" > $tmp_file2
    grep -v "^confluentinc|" $tmp_file >> $tmp_file2
    cat $tmp_dir/confluent-plugin-sourcecode-mapping-list.txt >> $tmp_file2
    cat $tmp_file2 | sort | uniq > $tmp_file
fi

cp $tmp_file $root_folder/scripts/cli/confluent-hub-plugin-list.txt