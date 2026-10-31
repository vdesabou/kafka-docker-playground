#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-ec2
# steps 1 to 3 create nothing on AWS (read-only calls, a dry run, the playground.ini reminder). Step 4 creates a small
# instance (billed, about 25 minutes) and only runs with PLAYGROUND_LAB_EC2_CREATE=1; it is deleted on exit whatever
# happens. Skipped without the aws CLI, without AWS credentials, or when they can't describe EC2 instances.
lab_require_plaintext

if ! command -v aws > /dev/null 2>&1
then
    logwarn "the aws CLI is not installed, skipping the ec2 lab"
    exit 111
fi
if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_PROFILE" ] && [ ! -f "$HOME/.aws/credentials" ]
then
    logwarn "no AWS credentials (AWS_ACCESS_KEY_ID, AWS_PROFILE or ~/.aws/credentials), skipping the ec2 lab"
    exit 111
fi

ROOT_FOLDER="$( cd "${DIR}/../.." >/dev/null && pwd )"
LAB_USER=$(whoami)
FAKE_INSTANCE_NAME="pg-${LAB_USER}-lab"
LAB_INSTANCE_NAME="pg-${LAB_USER}-deep-dive-lab"
LAB_PEM_FILE="${ROOT_FOLDER}/${LAB_INSTANCE_NAME}.pem"
LAB_INSTANCE_CREATED=0

OLD_RUNNING_LIST=$(playground state get ec2.running_list 2> /dev/null | tail -1)
OLD_PROFILE=$(playground config get secrets.profile)

# a throwaway store with the file backend, for push-secrets (also what step 4 pushes to the lab instance)
export PLAYGROUND_SECRETS_DIR=$(mktemp -d)
export PLAYGROUND_SECRETS_BACKEND=file
unset PLAYGROUND_SECRETS_PROFILE

function cleanup_ec2_lab () {
    set +e
    if [ "$LAB_INSTANCE_CREATED" = "1" ] || [ -f "$LAB_PEM_FILE" ]
    then
        log "🧹 deleting the lab instance $LAB_INSTANCE_NAME"
        playground ec2 delete --instance "$LAB_INSTANCE_NAME"
    fi
    if [ -n "$OLD_RUNNING_LIST" ]
    then
        playground state set ec2.running_list "$OLD_RUNNING_LIST" > /dev/null 2>&1
    else
        playground state del ec2.running_list > /dev/null 2>&1
    fi
    playground config set secrets.profile "${OLD_PROFILE:-default}" > /dev/null 2>&1
    rm -rf "$PLAYGROUND_SECRETS_DIR"
    set -e
}
trap cleanup_ec2_lab EXIT

log "Step 1: what you have, read-only"
lab_run playground ec2 list
if [ "$LAB_EXIT" != "0" ] && grep -qF "aws ec2 describe-instances command got an error" <<< "$LAB_OUTPUT"
then
    logwarn "these AWS credentials can't describe EC2 instances, skipping the ec2 lab"
    exit 111
fi
lab_expect_exit 0
lab_expect_contains "🔘 listing all your ec2 instances"
lab_run playground --output-level WARN ec2 list
lab_expect_exit 0
lab_expect_not_contains "listing all your ec2 instances" "the log line, with --output-level WARN"
lab_run playground ec2 status --instance "pg-${LAB_USER}-nothing-here"
lab_expect_exit 0
lab_expect_not_contains "running" "a state for an instance that doesn't exist"
lab_expect_not_contains "stopped" "a state for an instance that doesn't exist"

log "Step 2: what push-secrets would send, without contacting anything"
playground config set secrets.profile default > /dev/null
lab_run playground secrets set LAB_EC2_PASSWORD --value 'Demo-Passw0rd-1234'
lab_expect_exit 0
lab_run playground ec2 push-secrets --instance "${FAKE_INSTANCE_NAME}/✅running/ec2-lab.example.com/i-lab" --dry-run
lab_expect_exit 0
lab_expect_contains "1 variable(s) of profile default would be written to ~/.playground-secrets.properties on:"
lab_expect_contains "👉 ${FAKE_INSTANCE_NAME}"
lab_expect_not_contains "Demo-Passw0rd-1234" "the password in clear"

log "Step 3: the reminder of playground status"
lab_start_environment
playground state set ec2.running_list "$FAKE_INSTANCE_NAME"
lab_run playground status
lab_expect_contains "🤑 you have an ec2 instance ${FAKE_INSTANCE_NAME} running !"
playground state del ec2.running_list
lab_run playground status
lab_expect_not_contains "🤑 you have an ec2 instance ${FAKE_INSTANCE_NAME} running !" "the reminder, once the list is empty"

if [ "${PLAYGROUND_LAB_EC2_CREATE}" != "1" ]
then
    log "⏭️ step 4 creates an instance (billed): export PLAYGROUND_LAB_EC2_CREATE=1 to run it"
    log "✅ all the outputs of the page are as expected"
    exit 0
fi

log "Step 4: a small instance, end to end"
if [ -n "$(playground ec2 status --instance "$LAB_INSTANCE_NAME" --all)" ]
then
    logerror "❌ $LAB_INSTANCE_NAME already exists: delete it first with playground ec2 delete --instance $LAB_INSTANCE_NAME"
    # not ours: don't let the trap delete it
    LAB_PEM_FILE="/nonexistent/${LAB_INSTANCE_NAME}.pem"
    exit 1
fi
LAB_INSTANCE_CREATED=1
lab_run playground ec2 create --instance-type t2.large --size 50 --suffix deep-dive-lab
lab_expect_contains "🔐 creating pem file ${LAB_PEM_FILE} (make sure to create backup)"
lab_expect_contains "👷 creating t2.large instance ${LAB_INSTANCE_NAME} in"
lab_expect_contains "🟢 ec2 cloudformation ${LAB_INSTANCE_NAME} is in status CREATE_COMPLETE"
lab_expect_contains "✅ ~/.playground-secrets.properties written on ${LAB_INSTANCE_NAME}"
lab_expect_contains "🎉 ec2 instance ${LAB_INSTANCE_NAME} is ready!"
lab_run playground ec2 status --instance "$LAB_INSTANCE_NAME"
lab_expect_contains "✅running"
lab_run playground ec2 stop --instance "$(playground ec2 status --instance "$LAB_INSTANCE_NAME" --all)"
lab_expect_contains "🔴 stopping ec2 instance ${LAB_INSTANCE_NAME}"
lab_run playground ec2 delete --instance "$LAB_INSTANCE_NAME"
lab_expect_contains "❌ deleting ec2 cloudformation ${LAB_INSTANCE_NAME} in state"
lab_expect_contains "🔐 deleting pem file ${LAB_PEM_FILE}"
if [ -f "$LAB_PEM_FILE" ]
then
    logerror "❌ the pem file $LAB_PEM_FILE is still there after delete"
    exit 1
fi
LAB_INSTANCE_CREATED=0

log "✅ all the outputs of the page are as expected"
