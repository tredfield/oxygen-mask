#!/bin/bash

source $(dirname $0)/add-ssh-key.sh

repo=$1
output=$PWD/$2/pr_result
github_access_token=${GITHUB_ACCESS_TOKEN}
base=pr-metric
branch=pr-metric-push-branch

# checkout repo and create a base branch and branch for pull-request
logInfo "Clonging ${repo}..."
git clone git@github.com:scpprd/${repo}.git
cd ${repo}

logInfo "Checking out and pushing ${base}..."
git checkout -b ${base}
git push --set-upstream origin ${base}

logInfo "Checking out ${branch}..."
git checkout -b ${branch}

# current_val=$(cat pr-count-file)
# new_val=$((current_val +1))
new_val="for measuring pr metric"
echo $new_val > pr-count-file

# push commit to branch
logInfo "Pushing commit to ${branch}..."
git add pr-count-file
git commit -am"commit for measuring pr time"
git push --set-upstream origin ${branch}

# create pull-request
logInfo "Creating pull-request"
jq -c -n \
  --arg title "For measuring pull-request time" \
  --arg body "For measuring pull-request time" \
  --arg base "${base}" \
  --arg head "${branch}" \
  '{
    "title": $title,
    "body": $body,
    "base": $base,
    "head": $head
  }' | curl -H "Authorization: token $github_access_token" -d@- "https://api.github.com/repos/scpprd/${repo}/pulls" > ${output}
