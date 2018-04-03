#!/bin/bash

source $(dirname $0)/common.sh

github_access_token=$1
repo=$2
pull=$3

_sleep=5



# get the pull request
logInfo "Getting pull request for repository ${repo} and pull request # ${pull}"
pr=$(curl -s -H "Authorization: token $github_access_token" https://api.github.com/repos/scpprd/$repo/pulls/$pull)
status_href=$(echo $pr|jq  -r '._links.statuses.href')

# get statues and check count
statuses_count=0

while [ $statuses_count = 0 ]; do
  logInfo "Getting pull request statuses"
  statuses=$(curl -s -H "Authorization: token $github_access_token" $status_href)
  statuses_count=$(echo $statuses | jq -r '. | length')

  logInfo "Statuses count: ${statuses_count}"

  # proceed if statuses exist
  if [ $statuses_count != "0" ]; then
    pr_status="pending"

    while [ "$pr_status" = "pending" ]; do
      # get current status
      pr_status=$(echo $statuses | jq -r '[.[] | select(.context | contains("concourse-ci/status"))][0].state')

      logInfo "Current status: ${pr_status}"

      if [ "$pr_status" = "success" ]; then
        echo "Success!"
        exit 0
      fi

      if [ "$pr_status" = "failure" ]; then
        logError "PR Failed!"
        exit 1
      fi

      logError "Waiting on pending status. Sleeping ${_sleep} seconds"
      sleep ${_sleep}
    done
  fi

  logWarn "No status. Sleeping ${_sleep} seconds"
  sleep ${_sleep}
done

logError "Not able to obtain PR status!"
exit 2
