## [@bashly-upgrade validations]
validate_minimal_cp_version() {
  version="$1"
  if ! version_gt $version "4.9.99"
  then
      echo "CP version (--tag) must be > 5.0.0"
  fi
}
