#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

if [ -r ${DIR}/ccloud-cluster.properties ]
then
    . ${DIR}/ccloud-cluster.properties
else
    logerror "Cannot read configuration file ${APP_HOME}/ccloud-cluster.properties"
    exit 1
fi

verify_installed "kubectl"
verify_installed "helm"

if [ "${provider}" = "minikube" ]
then
    #######
    # minikube
    #######
    verify_installed "minikube"
    set +e
    log "Stop minikube if required"
    minikube delete
    set -e
    log "Start minikube"
    minikube start --cpus=8 --disk-size='50gb' --memory=16384
    log "Launch minikube dashboard in background"
    minikube dashboard &
elif [ "${provider}" = "aws" ]
then
    #######
    # aws
    #######
    # brew tap weaveworks/tap
    # brew install weaveworks/tap/eksctl
    # to upgrade
    # brew upgrade eksctl && brew link --overwrite eksctl
    verify_installed "eksctl"
    verify_installed "aws"
    set +e
    log "Stop EKS cluster if required"
    eksctl delete ${eks_cluster_name}
    set -e
    log "Start EKS cluster with ${eks_ec2_instance_type} instances"
    eksctl create cluster --name ${eks_cluster_name} \
        --version 1.18 \
        --node-type ${eks_ec2_instance_type} \
        --region ${eks_region} \
        --nodes ${eks_nodes} \
        --node-ami auto

    log "Configure your computer to communicate with your cluster"
    aws eks update-kubeconfig \
        --region ${eks_region} \
        --name ${eks_cluster_name}

    log "Deploy the Metrics Server"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    log "Deploy the Kubernetes dashboard"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.5/aio/deploy/recommended.yaml

    kubectl apply -f eks-admin-service-account.yaml

    log "Get the token from the output below to connect to dashboard"
    kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')

    kubectl proxy &
else
    logerror "Provider ${provider} is not supported"
    exit 1
fi

