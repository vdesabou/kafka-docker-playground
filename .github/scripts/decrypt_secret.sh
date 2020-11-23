#!/bin/sh

# --batch to prevent interactive command
# --yes to assume "yes" for questions
gpg --quiet --batch --yes --decrypt --passphrase="$SECRETS_ENCRYPTION_PASSWORD" --output secrets.tar secrets.tar.gpg
