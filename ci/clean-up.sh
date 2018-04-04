#!/bin/bash

source $(dirname $0)/add-ssh-key.sh

repo=$1
base=pr-metric
branch=pr-metric-push-branch

# checkout repo and create a base branch and branch for pull-request
logInfo "Cloning ${repo}..."
git clone git@github.com:scpprd/${repo}.git
cd ${repo}

logInfo "Deleting remote branches ${branch}, ${base}..."
git push origin --delete ${branch}
git push origin --delete ${base}
