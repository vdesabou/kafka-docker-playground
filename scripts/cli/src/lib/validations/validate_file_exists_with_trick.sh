## [@bashly-upgrade validations]
validate_file_exists_with_trick() {
  file="$1"
  real_file=$(echo "$file" | cut -d "@" -f 2)
  [[ -f "$real_file" ]] || echo "must be an existing file"
}
