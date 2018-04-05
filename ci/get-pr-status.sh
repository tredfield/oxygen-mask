#!/bin/bash

source $(dirname $0)/common.sh

github_access_token=$GITHUB_ACCESS_TOKEN
datadog_api_key=${DATADOG_API_KEY}

repo=$1
pull_request_output=$2
output=$PWD/$3

_sleep=5

#get the PR pull number
pull=$(cat $pull_request_output/pr_result | jq -r '.number')

# get the pull request
logInfo "Getting pull request for repository ${repo} and pull request # ${pull}"
pr=$(curl -s -H "Authorization: token $github_access_token" https://api.github.com/repos/scpprd/$repo/pulls/$pull)
status_href=$(echo $pr|jq  -r '._links.statuses.href')

# get statues and check count
statuses_count=0
pull_request_success=0

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
        logInfo "PR Success!"
        pull_request_success=1
      fi

      if [ "$pr_status" = "failure" ]; then
        logError "PR Failed!"
      fi

      if [ "$pr_status" = "pending" ]; then
        logError "Waiting on pending status. Sleeping ${_sleep} seconds"
        sleep ${_sleep}
        statuses=$(curl -s -H "Authorization: token $github_access_token" $status_href)
      fi
    done
  fi

  if [ $statuses_count = 0 ]; then
    logWarn "No status. Sleeping ${_sleep} seconds"
    sleep ${_sleep}
  fi
done

# write time in seconds
date +%s > ${output}/pr_end_time
pr_end_time=$(cat ${output}/pr_end_time)
pr_start_time=$(cat $pull_request_output/pr_start_time)
pr_duration=$((${pr_end_time}-${pr_start_time}))

pull_request=$(cat ${pull_request_output}/pr_result | jq -r '.id')
host_name=""
tags=""
postSeriesMetric "concourse.measure.pull.request.end" $pull_request $host_name $tags
postSeriesMetric "concourse.measure.pull.request.duration" $pr_duration $host_name $tags
postSeriesMetric "concourse.measure.pull.request.success" $pull_request_success $host_name $tags
