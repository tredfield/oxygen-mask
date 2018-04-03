#!/bin/bash

source $(dirname $0)/common.sh

set -e

export GIT_SSL_NO_VERIFY=true
export TMPDIR=${TMPDIR:-/tmp}

get_key() {
  key_path=$1
  prefix="-----BEGIN RSA PRIVATE KEY-----"
  suffix="-----END RSA PRIVATE KEY-----"
  gitkey=${GITHUB_PRIVATE_KEY#$prefix}
  gitkey=${gitkey%$suffix}

  cat > $key_path <<EOF
-----BEGIN RSA PRIVATE KEY-----
$(echo $gitkey | tr " " "\n")
-----END RSA PRIVATE KEY-----
EOF
}

load_key() {
  local private_key_path=$TMPDIR/git-resource-private-key

  get_key $private_key_path

  if [ -s $private_key_path ]; then
    chmod 0600 $private_key_path

    eval $(ssh-agent) >/dev/null 2>&1
    trap "kill $SSH_AGENT_PID" 0

    SSH_ASKPASS=$(dirname $0)/askpass.sh DISPLAY= ssh-add $private_key_path >/dev/null

    mkdir -p ~/.ssh
    cat > ~/.ssh/config <<EOF
StrictHostKeyChecking no
LogLevel quiet
EOF
    chmod 0600 ~/.ssh/config
  fi
}

if [ -n "$GITHUB_PRIVATE_KEY" ]; then
  logInfo "Adding ssh key${reset}"
  load_key
else
  logWarn "${green}No ssh key${reset}"
fi
