#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$CI" ]
then
   # not running with github actions
  verify_installed "minikube"
  minikube delete
else
  eksctl delete cluster --name kafka-docker-playground-ci
fi