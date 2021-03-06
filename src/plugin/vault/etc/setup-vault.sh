#!/bin/bash

set -euxo pipefail
export VAULT_ADDR='http://127.0.0.1:8200'
export PLUGIN_NAME='pachyderm'

# Make sure ent auth is enabled

pachctl version
which aws || pip install awscli --upgrade --user
if [[ "$(pachctl enterprise get-state)" = "No Pachyderm Enterprise token was found" ]]; then
  # Don't print token to stdout
  # This is very important, or we'd leak it in our CI logs
  set +x
  pachctl enterprise activate  $(aws s3 cp s3://pachyderm-engineering/test_enterprise_activation_code.txt -)
  set -x
fi
if ! pachctl auth list-admins; then
  echo 'admin' | pachctl auth activate
fi

echo "going to login to vault"
echo 'root' | vault login -
echo "logged into vault"

set +o pipefail
rm /tmp/vault-plugins/$PLUGIN_NAME || true
set -o pipefail

go build -o /tmp/vault-plugins/$PLUGIN_NAME src/plugin/vault/main.go 

# Clean up from last run
vault secrets disable $PLUGIN_NAME

# Enable the plugin
export SHASUM=$(shasum -a 256 "/tmp/vault-plugins/$PLUGIN_NAME" | cut -d " " -f1)
echo $SHASUM
vault write sys/plugins/catalog/$PLUGIN_NAME sha_256="$SHASUM" command="$PLUGIN_NAME"
vault secrets enable -path=$PLUGIN_NAME -plugin-name=$PLUGIN_NAME plugin
