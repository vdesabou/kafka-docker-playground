# deprecated since #9958: kept for the scripts and habits that still call it
logwarn "⚠️ 'playground ccloud-costs-history' is deprecated, use 'playground cloud-resources ccloud costs-history' (same flags)"
playground cloud-resources ccloud costs-history "${other_args[@]}"
