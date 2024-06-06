## [@bashly-upgrade validations]
validate_file_exists_and_parquet() {
  file="$1"

  real_file=$file
  if [[ $file == *"@"* ]]
  then
    real_file=$(echo "$file" | cut -d "@" -f 2)
  fi

  [[ -f "$real_file" ]] || logerror "<$real_file> does not correspond to the path of an existing file, please make sure to use absolute full path or correct relative path !"
  [[ "$real_file" == *.parquet ]] || logerror "<$real_file> is not an Parquet file. Please provide a file with .parquet extension."
}