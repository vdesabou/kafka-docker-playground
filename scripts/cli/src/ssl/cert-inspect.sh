#!/bin/bash
# run by 'playground tools cert inspect' inside the connect image (openssl 3 + keytool), the files in /work/in.
# Prints one tab separated record per line, read by the command:
#   ENTRY  <entry> <kind>                                    kind: PrivateKeyEntry, trustedCertEntry, pem, der, server
#   CERT   <entry> <index> <subject> <issuer> <serial> <not before epoch> <not after epoch> <sans> <key algorithm>
#          <key bits> <signature algorithm> <key usage> <extended key usage> <ca> <self signed> <sha256 fingerprint>
#   KEY    <entry> <match|mismatch|unreadable> <detail>
#   VERIFY <entry> <ok|fail> <detail>
#   TLS    <entry> <protocol> <cipher>
#   INFO   <message>
#   ERROR  <message>
# input (environment): FILE, KEY, TRUSTSTORE, PASSWORD, TRUSTSTORE_PASSWORD, SERVER, SERVERNAME (basenames in /work/in)

work=$(mktemp -d)
in=/work/in
tab=$'\t'

# empty fields are written as "-": bash read collapses consecutive tabs (a tab is IFS white space)
function out () {
  local IFS="$tab" field fields=()
  for field in "$@"
  do
    fields+=("${field:--}")
  done
  printf '%s\n' "${fields[*]}"
}

# one cert-NN.pem per certificate of a PEM file, in the order of the file
function split_pem () {
  awk -v d="$2" '/-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/cert-%02d.pem", d, n) } f { print > f } /-----END CERTIFICATE-----/ { f = "" }' "$1"
}

function ext () {
  # value of an x509v3 extension, on one line, without the header line
  openssl x509 -in "$1" -noout -ext "$2" 2> /dev/null | tail -n +2 | sed 's/^ *//' | paste -sd ' ' -
}

function describe_cert () {
  local entry="$1" index="$2" pem="$3"
  local subject issuer serial not_before not_after sans key_alg key_bits sig_alg ku eku ca self fp text
  subject=$(openssl x509 -in "$pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
  issuer=$(openssl x509 -in "$pem" -noout -issuer -nameopt RFC2253 | sed 's/^issuer=//')
  serial=$(openssl x509 -in "$pem" -noout -serial | cut -d= -f2)
  not_before=$(date -d "$(openssl x509 -in "$pem" -noout -startdate | cut -d= -f2)" +%s)
  not_after=$(date -d "$(openssl x509 -in "$pem" -noout -enddate | cut -d= -f2)" +%s)
  sans=$(ext "$pem" subjectAltName | sed 's/IP Address:/IP:/g; s/, /,/g')
  ku=$(ext "$pem" keyUsage)
  eku=$(ext "$pem" extendedKeyUsage)
  ca=$(ext "$pem" basicConstraints | grep -q "CA:TRUE" && echo true || echo false)
  text=$(openssl x509 -in "$pem" -noout -text)
  key_alg=$(grep -m1 "Public Key Algorithm:" <<< "$text" | sed 's/.*: //')
  key_bits=$(grep -m1 -oE "Public-Key: \([0-9]+ bit\)" <<< "$text" | grep -oE "[0-9]+")
  sig_alg=$(grep -m1 "Signature Algorithm:" <<< "$text" | sed 's/.*: //')
  self=no
  if [[ "$subject" == "$issuer" ]] && openssl verify -CAfile "$pem" "$pem" > /dev/null 2>&1
  then
    self=yes
  fi
  fp=$(openssl x509 -in "$pem" -noout -fingerprint -sha256 | cut -d= -f2)
  out CERT "$entry" "$index" "$subject" "$issuer" "$serial" "$not_before" "$not_after" "$sans" "$key_alg" "${key_bits:-?}" "$sig_alg" "$ku" "$eku" "$ca" "$self" "$fp"
}

# describes the certificates of a directory of cert-NN.pem, and keeps them for the verification
function describe_chain () {
  local entry="$1" dir="$2" i=0 pem
  for pem in "$dir"/cert-*.pem
  do
    [ -f "$pem" ] || continue
    i=$((i + 1))
    describe_cert "$entry" "$i" "$pem"
  done
  if [ $i -eq 0 ]
  then
    out ERROR "no certificate found in $entry"
    return 1
  fi
  chains+=("$entry$tab$dir")
}

# key_match <entry> <key file> <cert>: does the private key belong to the certificate?
function key_match () {
  local entry="$1" key="$2" cert="$3" pub_key pub_cert
  pub_key=$(openssl pkey -in "$key" -pubout -passin "pass:${PASSWORD}" 2> "$work/key.err")
  if [ -z "$pub_key" ]
  then
    out KEY "$entry" unreadable "$(head -1 "$work/key.err") (encrypted key: pass --password)"
    return
  fi
  pub_cert=$(openssl x509 -in "$cert" -noout -pubkey)
  if [[ "$pub_key" == "$pub_cert" ]]
  then
    out KEY "$entry" match "the private key belongs to the first certificate"
  else
    out KEY "$entry" mismatch "the private key does not belong to the first certificate ($(openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 | sed 's/^subject=//'))"
  fi
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

# keystore_password <file>: prints the password that opens the keystore (PASSWORD, or the usual ones when not set)
function keystore_password () {
  local file="$1" candidate
  local candidates=("$2")
  if [ -z "$2" ]
  then
    candidates=("" "confluent" "changeit")
  fi
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

# inspect_file <file> <password>: keystore (JKS / PKCS12), PEM (certificates, maybe a private key) or DER
function inspect_file () {
  local file="$1" password="$2" name dir alias kind store_pass
  name=$(basename "$file")
  if grep -q -- "-----BEGIN" "$file" 2> /dev/null
  then
    dir="$work/$name.pem.d"
    mkdir -p "$dir"
    split_pem "$file" "$dir"
    out ENTRY "$name" pem
    describe_chain "$name" "$dir" || return 1
    if grep -q -- "PRIVATE KEY-----" "$file"
    then
      key_match "$name" "$file" "$dir/cert-01.pem"
    fi
    return 0
  fi
  if openssl x509 -inform der -in "$file" -out "$work/$name.der.pem" > /dev/null 2>&1
  then
    dir="$work/$name.der.d"
    mkdir -p "$dir"
    mv "$work/$name.der.pem" "$dir/cert-01.pem"
    out ENTRY "$name" der
    describe_chain "$name" "$dir"
    return
  fi
  if ! store_pass=$(keystore_password "$file" "$password")
  then
    if [ -n "$password" ]
    then
      out ERROR "$name: cannot open the keystore with this password ($(keytool -list -keystore "$file" -storepass "$password" 2>&1 | grep -m1 -iE "error|exception" | sed 's/^keytool error: //'))"
    else
      out ERROR "$name: not a PEM or DER certificate, and not a keystore opening with an empty, 'confluent' or 'changeit' password: pass --password"
    fi
    return 1
  fi
  if [ -z "$password" ]
  then
    out INFO "$name: opened with the password '${store_pass}' (no --password)"
  fi
  out INFO "$name: keystore type $(keytool -list -keystore "$file" -storepass "$store_pass" 2> /dev/null | grep -m1 "Keystore type" | sed 's/.*: //')"
  # one entry per alias: the whole chain of a PrivateKeyEntry, the certificate of a trustedCertEntry
  split_keystore "$work/$name.ks" "$file" "$store_pass"
  while IFS="$tab" read -r n alias kind
  do
    [ -z "$alias" ] && continue
    out ENTRY "$name:$alias" "$kind"
    describe_chain "$name:$alias" "$work/$name.ks/$n"
  done < "$work/$name.ks/index"
}

# trust.pem: every certificate of the truststore
function load_truststore () {
  local file="$1" password="$2" store_pass
  if grep -q -- "-----BEGIN CERTIFICATE" "$file" 2> /dev/null
  then
    cp "$file" "$work/trust.pem"
  elif openssl x509 -inform der -in "$file" -out "$work/trust.pem" > /dev/null 2>&1
  then
    :
  elif store_pass=$(keystore_password "$file" "$password")
  then
    keytool -list -rfc -keystore "$file" -storepass "$store_pass" 2> /dev/null | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > "$work/trust.pem"
  else
    out ERROR "$(basename "${file#$in/truststore-}"): cannot open the truststore (pass --truststore-password)"
    return 1
  fi
  out INFO "truststore $(basename "${file#$in/truststore-}"): $(grep -c -- "-----BEGIN CERTIFICATE-----" "$work/trust.pem") certificate(s)"
}

chains=()

if [ -n "$SERVER" ]
then
  dir="$work/server.d"
  mkdir -p "$dir"
  sni="${SERVERNAME:-${SERVER%:*}}"
  timeout 20 openssl s_client -connect "$SERVER" -servername "$sni" -showcerts < /dev/null > "$work/s_client.out" 2> "$work/s_client.err"
  split_pem "$work/s_client.out" "$dir"
  if ! ls "$dir"/cert-*.pem > /dev/null 2>&1
  then
    out ERROR "no certificate from $SERVER: $(grep -m1 -iE "error|refused|unknown|timeout" "$work/s_client.err" "$work/s_client.out" | sed 's/^[^:]*://' | head -1)"
  else
    out ENTRY "$SERVER" server
    describe_chain "$SERVER" "$dir"
    cipher=$(grep -m1 -E "^ *Cipher *:" "$work/s_client.out" | sed 's/.*: *//')
    if [[ -z "$cipher" || "$cipher" == "0000" ]]
    then
      cipher=$(grep -m1 -oE "Cipher is [A-Za-z0-9_-]+" "$work/s_client.out" | sed 's/Cipher is //')
    fi
    out TLS "$SERVER" "$(grep -m1 -E "^ *Protocol *:" "$work/s_client.out" | sed 's/.*: *//')" "$cipher"
  fi
fi

if [ -n "$FILE" ]
then
  inspect_file "$in/$FILE" "$PASSWORD"
fi

if [ -n "$KEY" ] && [ ${#chains[@]} -gt 0 ]
then
  first_dir="${chains[0]#*$tab}"
  key_match "${chains[0]%%$tab*}" "$in/$KEY" "$first_dir/cert-01.pem"
fi

if [ -n "$TRUSTSTORE" ] && load_truststore "$in/$TRUSTSTORE" "$TRUSTSTORE_PASSWORD"
then
  for chain in "${chains[@]}"
  do
    entry="${chain%%$tab*}"
    dir="${chain#*$tab}"
    leaf="$dir/cert-01.pem"
    : > "$work/untrusted.pem"
    for pem in "$dir"/cert-*.pem
    do
      [[ "$pem" == "$leaf" ]] || cat "$pem" >> "$work/untrusted.pem"
    done
    untrusted=()
    [ -s "$work/untrusted.pem" ] && untrusted=(-untrusted "$work/untrusted.pem")
    # -partial_chain: like java, a truststore with the intermediate (not the root) is enough
    if result=$(openssl verify -partial_chain -CAfile "$work/trust.pem" "${untrusted[@]}" "$leaf" 2>&1)
    then
      out VERIFY "$entry" ok "trusted"
    else
      out VERIFY "$entry" fail "$(grep -m1 -E "^error" <<< "$result" | sed 's/^error [0-9]* at [0-9]* depth lookup: //')"
    fi
  done
fi
