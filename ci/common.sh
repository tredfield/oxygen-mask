#!/bin/bash

# params from tasks/pipeline
host_name=${CONCOURSE_TARGET_URL}
team=${CONCOURSE_TARGET_TEAM}
build_pipeline=${CONCOURSE_TARGET_PIPELINE}
tags="team:${team}, pipeline:${build_pipeline}"

# output colors
declare -r _RED='\033[0;31m'
declare -r _YELLOW='\033[1;33m'
declare -r _GREEN='\033[0;32m'
declare -r _BLUE='\033[1;34m'
declare -r _RESET='\033[0m'

logInfo() {
  echo -e "${_GREEN}${1}${_RESET}"
}

logWarn() {
  echo -e "${_YELLOW}${1}${_RESET}"
}

logError() {
  echo -e  "${_RED}${1}${_RESET}"
}

postSeriesMetric() {
  metric_name=$1
  metric_value=$2
  currenttime=$(date +%s)

  logInfo "Posting metric ${metric_name} with value ${metric_value} for host ${host_name} and tags ${tags}"
  curl -s -X POST -H "Content-type: application/json" \
  -d "{ \"series\" :
           [{\"metric\":\"$metric_name\",
            \"points\":[[$currenttime, $metric_value]]},
            \"host\":\"${host_name}\",
            \"tags\":[\"${tags}\"]}]
  }" \
  "https://api.datadoghq.com/api/v1/series?api_key=$datadog_api_key"
}


postStatus() {
  commit_status=$1
  repo=$2
  commitsha=$3
  target_url="http://ci-cfs.use1-cfs-mc.int.scpdev.net:8080/teams/main/pipelines/pull-request-metric/jobs/measure-pull-request/builds/1"
  description="testing status"
  jq -c -n \
    --arg status "$commit_status" \
    --arg target_url "$target_url" \
    --arg description "$description" \
    --arg context "concourse-ci/status" \
    '{
      "state": $status,
      "target_url": $target_url,
      "description": $description,
      "context": $context
    }' | curl -H "Authorization: token $github_access_token" -d@- "https://api.github.com/repos/scpprd/$repo/statuses/$commitsha"
}
