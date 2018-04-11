#!/bin/bash

source $(dirname $0)/add-ssh-key.sh

output=$PWD/$1
repo=${REPO}
base=${METRICS_BASE}
github_access_token=${GITHUB_ACCESS_TOKEN}
datadog_api_key=${DATADOG_API_KEY}

# write time
date_seconds=$(date +%s)

cloneRepoAndGetBranches() {
  branch="pr-metric-push-branch-${date_seconds}"

  # checkout repo and create a base branch and branch for pull-request
  logInfo "Cloning ${repo}..."
  git clone git@github.com:scpprd/${repo}.git
  cd ${repo}

  base_found=$(git branch -r | grep ${base})

  if [ -z "${base_found}" ]; then
    logInfo "Checking out and pushing ${base}..."
    git checkout -b ${base}
    git push --set-upstream origin ${base}
  else
    git checkout ${base}
  fi

  logInfo "Checking out ${branch}..."
  git checkout -b ${branch}
}

pushCommit() {
  # current_val=$(cat pr-count-file)
  # new_val=$((current_val +1))
  new_val="for measuring pr metric"
  echo $new_val > pr-count-file
  date >> pr-count-file

  # push commit to branch
  logInfo "Pushing commit to ${branch}..."
  git add pr-count-file
  git commit -am"commit for measuring pr time"
  git push --set-upstream origin ${branch}
}

createPr() {
  # create pull-request
  logInfo "Creating pull-request..."
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
    }' | curl -H "Authorization: token $github_access_token" -d@- "https://api.github.com/repos/scpprd/${repo}/pulls" > ${output}/pr_result
}

writeOutput() {
  # write time
  date +%s > ${output}/pr_start_time

  pull_request=$(cat ${output}/pr_result | jq -r '.id')
  postSeriesMetric "concourse.measure.pull.request.start" $pull_request

  pr_url=$(cat ${output}/pr_result | jq -r '.html_url')
  echo ""
  logInfo "Created pull request ${pr_url}"

  # write output
  echo $base > ${output}/pr_base_name
  echo $branch > ${output}/pr_branch_name
}

# main app
cloneRepoAndGetBranches
pushCommit
createPr
writeOutput
