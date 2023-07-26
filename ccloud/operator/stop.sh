#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GITHUB_RUN_NUMBER" ]
then
   # not running with github actions
  verify_installed "minikube"
  minikube delete
else
  tag=$(echo "$TAG" | sed -e 's/\.//g')
  eksctl delete cluster --name kafka-docker-playground-ci-$tag
fi