function get_environment_used() {
  if [ ! -f /tmp/playground-command ]
  then
    echo "error"
    return
  fi

  grep "environment/2way-ssl" /tmp/playground-command > /dev/null
  if [ $? = 0 ]
  then
    echo "2way-ssl"
    return
  fi

  grep "environment/sasl-ssl" /tmp/playground-command > /dev/null
  if [ $? = 0 ]
  then
    echo "sasl-ssl"
    return
  fi

  echo "plaintext"
}
