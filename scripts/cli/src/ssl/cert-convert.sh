#!/bin/bash
# run by 'playground tools cert convert' inside the connect image (openssl 3 + keytool): converts /work/in/$FILE (and
# /work/in/$KEY) to $TO in /work/out. Prints one tab separated record per line, read by the command:
#   OUT   <file> <what>          a file written in /work/out
#   INFO  <message>
#   ERROR <message>
# input (environment): FILE, KEY, PASSWORD, OUTPUT_PASSWORD, TO (pkcs12, jks, pem, der, properties), ALIAS, BASE

in=/work/in
out=/work/out
work=$(mktemp -d)
tab=$'\t'
mkdir -p "$out"

function rec () {
  local IFS="$tab"
  printf '%s\n' "$*"
}

function split_pem () {
  awk -v d="$2" '/-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/cert-%02d.pem", d, n) } f { print > f } /-----END CERTIFICATE-----/ { f = "" }' "$1"
}

function cn_of () {
  openssl x509 -in "$1" -noout -subject -nameopt RFC2253 2> /dev/null | sed -E 's/^subject=//; s/^.*CN=([^,]*).*$/\1/' | tr -c 'A-Za-z0-9._-' '_' | sed 's/_*$//'
}

function keystore_password () {
  local file="$1" candidate
  local candidates=("$2")
  [ -z "$2" ] && candidates=("" "confluent" "changeit")
  for candidate in "${candidates[@]}"
  do
    if keytool -list -keystore "$file" -storepass "$candidate" > /dev/null 2>&1
    then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# Kafka properties value of a PEM file: each PEM line ends with a \n escape (a real newline once loaded) and continues
# with a backslash. Kafka's PEM parser needs a white space after each -----END ...----- marker: without the \n, the last
# certificate of the value is not found (a one certificate truststore is refused, a chain loses its last certificate)
function properties_value () {
  awk '{ sub(/\r$/, "") } NF { lines[++n] = $0 } END { for (i = 1; i <= n; i++) printf "%s\\n%s\n", lines[i], (i < n ? "\\" : "") }' "$1"
}

# every entry of a keystore in one keytool call (one call per alias is slow on a truststore of the JDK CAs): $1/index
# holds "<n>\t<alias>\t<entry type>", $1/<n>/cert-NN.pem the certificates of entry n (the whole chain of a key pair entry)
function split_keystore () {
  local dir="$1" file="$2" pass="$3"
  mkdir -p "$dir"
  # tr: keytool -rfc writes CRLF line ends (MIME base64), and a \r ends a line of a Kafka properties file
  keytool -list -rfc -keystore "$file" -storepass "$pass" 2> /dev/null | tr -d '\r' | awk -v d="$dir" '
    /^Alias name: / { n++; alias = substr($0, 13); c = 0; system("mkdir -p \"" d "/" n "\""); next }
    /^Entry type: / { print n "\t" alias "\t" substr($0, 13) > (d "/index"); next }
    /-----BEGIN CERTIFICATE-----/ { c++; f = sprintf("%s/%d/cert-%02d.pem", d, n, c) }
    f { print > f }
    /-----END CERTIFICATE-----/ { close(f); f = "" }'
  touch "$dir/index"
}

store_type() {
  case "$1" in
    pkcs12) echo PKCS12 ;;
    jks) echo JKS ;;
  esac
}

extension() {
  case "$1" in
    pkcs12) echo p12 ;;
    jks) echo jks ;;
  esac
}

# ---------------------------------------------------------------------------------------------------------------------
# what the input is: a keystore (store_pass), PEM certificates (+ key), or a DER certificate
file="$in/$FILE"
kind=""
if grep -q -- "-----BEGIN" "$file" 2> /dev/null
then
  kind=pem
  mkdir -p "$work/certs"
  split_pem "$file" "$work/certs"
  if grep -q -- "PRIVATE KEY-----" "$file"
  then
    awk '/-----BEGIN .*PRIVATE KEY-----/,/-----END .*PRIVATE KEY-----/' "$file" > "$work/key.pem"
  fi
  if [ -n "$KEY" ]
  then
    cp "$in/$KEY" "$work/key.pem"
  fi
  if ! ls "$work/certs"/cert-*.pem > /dev/null 2>&1
  then
    rec ERROR "$FILE has no certificate (-----BEGIN CERTIFICATE-----)"
    exit 1
  fi
elif openssl x509 -inform der -in "$file" -out "$work/der.pem" > /dev/null 2>&1
then
  kind=der
  mkdir -p "$work/certs"
  mv "$work/der.pem" "$work/certs/cert-01.pem"
elif store_pass=$(keystore_password "$file" "$PASSWORD")
then
  kind=keystore
  [ -z "$PASSWORD" ] && rec INFO "$FILE: opened with the password '${store_pass}' (no --password)"
  src_type=$(keytool -list -keystore "$file" -storepass "$store_pass" 2> /dev/null | grep -m1 "Keystore type" | sed 's/.*: //')
  rec INFO "$FILE: keystore type $src_type"
else
  rec ERROR "$FILE: not a PEM or DER certificate, and not a keystore opening with $( [ -n "$PASSWORD" ] && echo "this password" || echo "an empty, 'confluent' or 'changeit' password: pass --password")"
  exit 1
fi

out_pass="${OUTPUT_PASSWORD:-${store_pass:-confluent}}"
if [ ${#out_pass} -lt 6 ] && [[ "$TO" == "pkcs12" || "$TO" == "jks" ]]
then
  rec ERROR "keytool needs an output password of at least 6 characters: pass --output-password"
  exit 1
fi

# key entries and trusted entries of a keystore, as PEM: $work/entries/<alias>/{chain.pem,key.pem} and $work/trusted.pem
function keystore_to_pem () {
  local n alias entry_kind p12
  mkdir -p "$work/entries"
  : > "$work/trusted.pem"
  split_keystore "$work/ks" "$file" "$store_pass"
  while IFS="$tab" read -r n alias entry_kind
  do
    [ -z "$alias" ] && continue
    if [ -n "$ALIAS" ] && [ "$alias" != "$ALIAS" ]
    then
      continue
    fi
    if [ "$entry_kind" == "PrivateKeyEntry" ]
    then
      mkdir -p "$work/entries/$alias"
      cat "$work/ks/$n"/cert-*.pem > "$work/entries/$alias/chain.pem"
      # the key: through a PKCS12 with this entry only (keytool cannot export a key); -legacy for the RC2 of old JDKs
      p12="$work/entries/$alias/entry.p12"
      keytool -importkeystore -srckeystore "$file" -srcstorepass "$store_pass" -srcalias "$alias" -destkeystore "$p12" \
        -deststoretype PKCS12 -deststorepass "$store_pass" -destkeypass "$store_pass" -noprompt > /dev/null 2> "$work/import.err" \
        || { rec ERROR "alias $alias: $(grep -m1 -iE "error|exception" "$work/import.err") (a key password different from the store password is not supported)"; continue; }
      if ! openssl pkcs12 -in "$p12" -nocerts -nodes -passin "pass:$store_pass" 2> "$work/key.err" | awk '/-----BEGIN .*PRIVATE KEY-----/,/-----END .*PRIVATE KEY-----/' > "$work/entries/$alias/key.pem" || [ ! -s "$work/entries/$alias/key.pem" ]
      then
        openssl pkcs12 -legacy -in "$p12" -nocerts -nodes -passin "pass:$store_pass" 2> "$work/key.err" | awk '/-----BEGIN .*PRIVATE KEY-----/,/-----END .*PRIVATE KEY-----/' > "$work/entries/$alias/key.pem"
      fi
      if [ ! -s "$work/entries/$alias/key.pem" ]
      then
        rec ERROR "alias $alias: could not read the private key ($(head -1 "$work/key.err"))"
      fi
    elif [ "$entry_kind" == "trustedCertEntry" ]
    then
      cat "$work/ks/$n"/cert-*.pem >> "$work/trusted.pem"
    fi
  done < "$work/ks/index"
  if [ -n "$ALIAS" ] && [ ! -d "$work/entries/$ALIAS" ] && [ ! -s "$work/trusted.pem" ]
  then
    rec ERROR "no alias $ALIAS in $FILE (aliases: $(cut -f2 "$work/ks/index" | paste -sd ' ' -))"
    exit 1
  fi
}

# PEM key, written as PKCS#8 encrypted with the output password (what Kafka's ssl.keystore.key expects), or not
function write_key () {
  local src="$1" dest="$2" encrypt="$3"
  if [ -n "$encrypt" ]
  then
    openssl pkcs8 -topk8 -v2 aes-256-cbc -in "$src" -passin "pass:$PASSWORD" -out "$dest" -passout "pass:$out_pass" 2> "$work/pkcs8.err"
  else
    openssl pkcs8 -topk8 -nocrypt -in "$src" -passin "pass:$PASSWORD" -out "$dest" 2> "$work/pkcs8.err"
  fi
}

case "$TO" in
  pkcs12|jks)
    target="$out/$BASE.$(extension "$TO")"
    if [ "$kind" == "keystore" ]
    then
      if [ "$(tr '[:lower:]' '[:upper:]' <<< "$src_type")" == "$(store_type "$TO")" ] && [ -z "$OUTPUT_PASSWORD" ] && [ -z "$ALIAS" ]
      then
        rec ERROR "$FILE is already a $(store_type "$TO") keystore (pass --output-password to change its password, or --alias to keep one entry)"
        exit 1
      fi
      alias_args=()
      [ -n "$ALIAS" ] && alias_args=(-srcalias "$ALIAS" -destalias "$ALIAS")
      if ! keytool -importkeystore -srckeystore "$file" -srcstorepass "$store_pass" "${alias_args[@]}" -destkeystore "$target" \
          -deststoretype "$(store_type "$TO")" -deststorepass "$out_pass" -destkeypass "$out_pass" -noprompt > "$work/import.out" 2>&1
      then
        rec ERROR "keytool -importkeystore: $(grep -m1 -iE "error|exception" "$work/import.out")"
        exit 1
      fi
      rec OUT "$(basename "$target")" "$(store_type "$TO") keystore, same entries as $FILE ($(grep -m1 -oE "[0-9]+ entries successfully imported|Entry for alias .* successfully imported" "$work/import.out"))"
    elif [ -s "$work/key.pem" ]
    then
      # key + chain: a key pair entry, named after the CN of the certificate unless --alias
      alias="${ALIAS:-$(cn_of "$work/certs/cert-01.pem")}"
      alias="${alias:-key}"
      cat "$work/certs"/cert-*.pem > "$work/chain.pem"
      if ! openssl pkcs12 -export -in "$work/chain.pem" -inkey "$work/key.pem" -passin "pass:$PASSWORD" -name "$alias" -out "$work/entry.p12" -passout "pass:$out_pass" 2> "$work/export.err"
      then
        rec ERROR "openssl pkcs12 -export: $(grep -m1 -iE "error|unable|mismatch" "$work/export.err" || head -1 "$work/export.err") (does the key belong to the first certificate? 'playground tools cert inspect' tells)"
        exit 1
      fi
      if [ "$TO" == "pkcs12" ]
      then
        mv "$work/entry.p12" "$target"
      else
        keytool -importkeystore -srckeystore "$work/entry.p12" -srcstoretype PKCS12 -srcstorepass "$out_pass" -destkeystore "$target" \
          -deststoretype JKS -deststorepass "$out_pass" -destkeypass "$out_pass" -noprompt > /dev/null 2>&1
      fi
      rec OUT "$(basename "$target")" "$(store_type "$TO") keystore: key pair entry '$alias' (private key + $(ls "$work/certs"/cert-*.pem | wc -l | tr -d ' ') certificate(s) of chain)"
    else
      # certificates only: a truststore, one trusted entry per certificate
      n=0
      for pem in "$work/certs"/cert-*.pem
      do
        n=$((n + 1))
        alias=$(cn_of "$pem")
        [ -n "$ALIAS" ] && alias="$ALIAS$( [ $n -gt 1 ] && echo "-$n")"
        alias="${alias:-cert-$n}"
        keytool -importcert -noprompt -alias "$alias" -file "$pem" -keystore "$target" -storetype "$(store_type "$TO")" -storepass "$out_pass" > /dev/null 2> "$work/importcert.err" \
          || keytool -importcert -noprompt -alias "$alias-$n" -file "$pem" -keystore "$target" -storetype "$(store_type "$TO")" -storepass "$out_pass" > /dev/null 2>&1
      done
      rec OUT "$(basename "$target")" "$(store_type "$TO") truststore: $n trusted certificate(s)"
    fi
  ;;

  pem)
    case "$kind" in
      pem)
        rec ERROR "$FILE is already PEM"
        exit 1
      ;;
      der)
        cp "$work/certs/cert-01.pem" "$out/$BASE.pem"
        rec OUT "$BASE.pem" "PEM certificate"
      ;;
      keystore)
        keystore_to_pem
        for dir in "$work/entries"/*/
        do
          [ -d "$dir" ] || continue
          alias=$(basename "$dir")
          cp "$dir/chain.pem" "$out/$BASE-$alias.certificate.pem"
          rec OUT "$BASE-$alias.certificate.pem" "certificate chain of '$alias' ($(grep -c -- "-----BEGIN CERTIFICATE-----" "$dir/chain.pem") certificate(s), the first one is its own): librdkafka ssl.certificate.location"
          if [ -s "$dir/key.pem" ]
          then
            if write_key "$dir/key.pem" "$out/$BASE-$alias.key.pem" "$OUTPUT_PASSWORD"
            then
              rec OUT "$BASE-$alias.key.pem" "private key of '$alias' (PKCS#8, $( [ -n "$OUTPUT_PASSWORD" ] && echo "encrypted with --output-password: librdkafka ssl.key.password" || echo "not encrypted: keep it private")): librdkafka ssl.key.location"
            fi
          fi
        done
        if [ -s "$work/trusted.pem" ]
        then
          trust_name="$BASE.truststore.pem"
          [[ "$BASE" == *truststore* ]] && trust_name="$BASE.pem"
          cp "$work/trusted.pem" "$out/$trust_name"
          rec OUT "$trust_name" "$(grep -c -- "-----BEGIN CERTIFICATE-----" "$work/trusted.pem") trusted certificate(s) (CA bundle): librdkafka ssl.ca.location"
        fi
      ;;
    esac
  ;;

  der)
    if [ "$kind" == "der" ]
    then
      rec ERROR "$FILE is already DER"
      exit 1
    fi
    if [ "$kind" == "keystore" ]
    then
      keystore_to_pem
      for dir in "$work/entries"/*/
      do
        [ -d "$dir" ] || continue
        alias=$(basename "$dir")
        split_pem "$dir/chain.pem" "$dir"
        openssl x509 -in "$dir/cert-01.pem" -outform der -out "$out/$BASE-$alias.der"
        rec OUT "$BASE-$alias.der" "DER certificate of '$alias' (the first of its chain)"
      done
    else
      openssl x509 -in "$work/certs/cert-01.pem" -outform der -out "$out/$BASE.der"
      rec OUT "$BASE.der" "DER certificate (the first of $FILE)"
    fi
  ;;

  properties)
    props="$out/$BASE.properties"
    key_pem=""
    chain_pem=""
    trust_pem=""
    if [ "$kind" == "keystore" ]
    then
      keystore_to_pem
      entry_dir=$(ls -d "$work/entries"/*/ 2> /dev/null | head -1)
      if [ -n "$entry_dir" ]
      then
        [ "$(ls -d "$work/entries"/*/ | wc -l)" -gt 1 ] && rec INFO "several key pair entries: the first one ($(basename "$entry_dir")) is used, pass --alias to choose"
        chain_pem="$entry_dir/chain.pem"
        key_pem="$entry_dir/key.pem"
      fi
      [ -s "$work/trusted.pem" ] && trust_pem="$work/trusted.pem"
    else
      cat "$work/certs"/cert-*.pem > "$work/chain.pem"
      if [ -s "$work/key.pem" ]
      then
        chain_pem="$work/chain.pem"
        key_pem="$work/key.pem"
      else
        trust_pem="$work/chain.pem"
      fi
    fi
    {
      echo "# Kafka client properties with the certificates inline (KIP-651, Apache Kafka 2.7+ / Confluent Platform 6.1+),"
      echo "# generated by 'playground tools cert convert' from $FILE: no keystore or truststore file to copy"
      if [ -n "$chain_pem" ] && [ -s "$key_pem" ]
      then
        write_key "$key_pem" "$work/key.p8" yes
        echo "ssl.keystore.type=PEM"
        echo "ssl.keystore.certificate.chain=$(properties_value "$chain_pem")"
        echo "ssl.keystore.key=$(properties_value "$work/key.p8")"
        echo "ssl.key.password=$out_pass"
      fi
      if [ -n "$trust_pem" ]
      then
        echo "ssl.truststore.type=PEM"
        echo "ssl.truststore.certificates=$(properties_value "$trust_pem")"
      fi
    } > "$props"
    what=""
    [ -n "$chain_pem" ] && what="ssl.keystore.* (key + $(grep -c -- "-----BEGIN CERTIFICATE-----" "$chain_pem") certificate(s))"
    [ -n "$trust_pem" ] && what="${what:+$what, }ssl.truststore.* ($(grep -c -- "-----BEGIN CERTIFICATE-----" "$trust_pem") trusted certificate(s))"
    if [ -z "$what" ]
    then
      rec ERROR "nothing to write: no key pair entry nor certificate in $FILE"
      exit 1
    fi
    rec OUT "$BASE.properties" "Kafka client properties with PEM inline: $what"
  ;;
esac
