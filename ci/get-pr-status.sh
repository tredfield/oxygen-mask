#!/bin/bash

source $(dirname $0)/common.sh

github_access_token=${GITHUB_ACCESS_TOKEN}
datadog_api_key=${DATADOG_API_KEY}
atc_url=${CONCOURSE_TARGET_URL}
team=${CONCOURSE_TARGET_TEAM}
build_pipeline=${CONCOURSE_TARGET_PIPELINE}

repo=$1
pull_request_output=$2
output=$PWD/$3
_sleep=10
host_name="${atc_url}"
tags=""

emitConcourseFoundVersion() {
  if [ -z "$concourse_pr_found" ]; then
    # get concourse versions and see if has PR
    versions=$(curl -s ${atc_url}/api/v1/teams/${team}/pipelines/${build_pipeline}/resources/pr-${repo}/versions)
    pr_version=$(echo $versions | jq  --arg pull "$pull" '.[] | select(.version.pr == $pull) | .version.pr')

    if [ -n "$pr_version" ]; then
      concourse_pr_found="true"
      pr_version_found_time=$(date +%s)
      pr_version_found_duration=$((${pr_version_found_time}-${pr_start_time}))
      logInfo "Concourse found pull request #${pull} in (seconds): ${pr_version_found_duration}"
      postSeriesMetric "concourse.measure.pull.request.pr.version.found.duration" $pr_version_found_duration $host_name $tags
    fi
  fi
}

initPullRequest() {
  # get the time the pr was created
  pr_start_time=$(cat $pull_request_output/pr_start_time)

  #get the PR pull number
  pull=$(cat $pull_request_output/pr_result | jq -r '.number')

  # get the pull request
  logInfo "Getting pull request for repository ${repo} and pull request # ${pull}"
  pr=$(curl -s -H "Authorization: token $github_access_token" https://api.github.com/repos/scpprd/$repo/pulls/$pull)
  status_href=$(echo $pr|jq  -r '._links.statuses.href')

  # get statues and check count
  statuses_count=0
  pull_request_success=0
}

getStatuses() {
  # calculate time waiting for concourse job to start and post metric
  pr_job_start_time=$(date +%s)
  pr_job_start_duration=$((${pr_job_start_time}-${pr_start_time}))

  logInfo "Getting pull request statuses"
  statuses=$(curl -s -H "Authorization: token $github_access_token" $status_href)
  statuses_count=$(echo $statuses | jq -r '. | length')

  logInfo "Statuses count: ${statuses_count}"
  logInfo "Current wait time (seconds): $pr_job_start_duration"
}

processStatues() {
  pr_status="pending"

  # record time spent waiting for PR job to start
  echo "$pr_job_start_time" > ${output}/pr_job_start_time
  postSeriesMetric "concourse.measure.pull.request.start.duration" $pr_job_start_duration $host_name $tags

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
}

pollStatus() {
  while [ $statuses_count = 0 ]; do
    getStatuses
    emitConcourseFoundVersion

    # proceed if statuses exist
    if [ $statuses_count != "0" ]; then
      processStatues
    fi

    # still waiting for statues?
    if [ $statuses_count = 0 ]; then
      logWarn "No status. Sleeping ${_sleep} seconds"
      sleep ${_sleep}
    fi
  done
}

emitFinishMetrics() {
  # write time in seconds
  date +%s > ${output}/pr_end_time
  pr_end_time=$(cat ${output}/pr_end_time)
  pr_start_time=$(cat $pull_request_output/pr_start_time)
  pr_duration=$((${pr_end_time}-${pr_start_time}))

  pull_request=$(cat ${pull_request_output}/pr_result | jq -r '.id')
  postSeriesMetric "concourse.measure.pull.request.end" $pull_request $host_name $tags
  postSeriesMetric "concourse.measure.pull.request.duration" $pr_duration $host_name $tags
  postSeriesMetric "concourse.measure.pull.request.success" $pull_request_success $host_name $tags
}

initPullRequest
pollStatus
emitFinishMetrics
