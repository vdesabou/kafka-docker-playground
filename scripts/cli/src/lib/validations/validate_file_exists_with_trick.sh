## [@bashly-upgrade validations]
validate_file_exists_with_trick() {
  file="$1"

  real_file=$file
  if [[ $file == *"@"* ]]
  then
    real_file=$(echo "$file" | cut -d "@" -f 2)
  fi
  
  [[ -f "$real_file" ]] || echo "$real_file must be an existing file"
}
