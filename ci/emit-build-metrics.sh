#!/bin/bash

source $(dirname $0)/add-ssh-key.sh

output=$PWD/$1
pull_request_output=$2
github_access_token=${GITHUB_ACCESS_TOKEN}
datadog_api_key=${DATADOG_API_KEY}
do_merge=${DO_MERGE}
versions=

getMergeCommit() {
  pr_number=$(cat ${pull_request_output}/pr_result | jq -r '.number')
  logInfo "Attempting to get merge commit from pull-request https://github.com/scpprd/${repo}/pull/${pr_number}"
  merged="false"

  while [ "${merged}" = "false" ]; do
    pull_request=$(curl -s -H "Authorization: token $GITHUB_ACCESS_TOKEN" "https://api.github.com/repos/scpprd/${repo}/pulls/${pr_number}")
    merged=$(echo ${pull_request} | jq -r '.merged')

    if [ "${merged}" = "false" ]; then
      logWarn "Merge commit not found. Sleeping 1 minute"
      sleep 60
    else
      merge_commit_sha=$(echo ${pull_request} | jq -r '.merge_commit_sha')
      logWarn "Merge commit ${merge_commit_sha} found..."
      merged_at=$(echo $pull_request | jq -r '.merged_at')
      merged_at=$(echo "${merged_at}" | sed 's/T/ /' | sed 's/Z//')
      merged_at=$(date --utc --date="$merged_at" +"%s")
    fi
  done
}

getMergeTime() {
  create_at=$(cat $pull_request_output/pr_result | jq -r '.merged_at')
  create_at=$(echo "${create_at}" | sed 's/T/ /' | sed 's/Z//')
  echo $(date --utc --date="$create_at" +"%s")
}

wait_time() {
  current_time=$(date +%s)
  wait_time=$((${current_time}-${merged_at}))
  echo "$wait_time"
}

cloneRepoAndMergePrBranchToBase() {
  if [[ "${do_merge}" == "true" ]]; then
    branch=$(cat $pull_request_output/pr_branch_name)
    base=$(cat $pull_request_output/pr_base_name)

    # checkout repo and create a base branch and branch for pull-request
    logInfo "Cloning ${repo}..."
    git clone git@github.com:scpprd/${repo}.git
    cd ${repo}

    logInfo "Checking out ${base}..."
    git checkout ${base}
    git merge origin/${branch}
    git push

    # save commit`and time
    merged_at=$(date +%s)
    merge_commit_sha=$(git rev-parse HEAD)
    echo ${merge_commit_sha} > ${output}/commit_sha
  fi
}

getVersions() {
  # get concourse versions and see if has PR
  versions=$(curl -s ${host_name}/api/v1/teams/${team}/pipelines/${build_pipeline}/resources/git-${manifest_repo}/versions)
  version_id=$(echo $versions | jq -r --arg commit "$merge_commit_sha" '.[] | select(.version.ref == $commit) | .id')

  if [ -n "$version_id" ]; then
    waiting=$(wait_time)
    logWarn "Concourse found merge commit ${merge_commit_sha} in (seconds): ${waiting}"
    postSeriesMetric "concourse.measure.merge.version.found.duration" ${waiting}
  fi
}

pollVersions() {
  while [ -z "$version_id" ]; do
    getVersions

    # proceed if version_id found
    if [ -n "$version_id" ]; then
      pollBuildStatus
    fi

    # still waiting for version?
    if [ -z "$version_id" ]; then
      waiting=$(wait_time)
      logWarn "No concourse merge version found. Sleeping ${_sleep} seconds. Total waiting time (seconds): ${waiting}"
      sleep ${_sleep}
    fi
  done
}

emitBuildStarted() {
  if [[ ("${build_status}" == "started" && -z "${start_emitted}") ]]; then
    waiting=$(wait_time)
    postSeriesMetric "concourse.measure.merge.build.started.duration" ${waiting}
    start_emitted="true"
  fi
}

pollBuildStatus() {
    build_status="pending"

    while [[ ("${build_status}" == "pending" || "${build_status}" == "started") ]]; do
      logInfo "Checking build status for commit ${merge_commit_sha} for pipeline ${build_pipeline} and repo ${manifest_repo}"
      version_input_to=$(curl -s ${host_name}/api/v1/teams/${team}/pipelines/${build_pipeline}/resources/git-${manifest_repo}/versions/${version_id}/input_to)
      statuses_count=$(echo $version_input_to | jq -r '. | length')

      logInfo "Status count: $statuses_count"

      if [ $statuses_count = 0 ]; then
        waiting=$(wait_time)
        logWarn "No statues. Sleeping ${_sleep} seconds. Total waiting time (seconds): ${waiting}"
        sleep ${_sleep}
      else
        build_status=$(echo $version_input_to | jq -r '.[0].status')

        # post metric for duration to start build
        emitBuildStarted

        # still waiting for status?
        if [[ ("${build_status}" == "pending" || "${build_status}" == "started") ]]; then
          waiting=$(wait_time)
          logWarn "Status is ${build_status}. Sleeping ${_sleep} seconds. Total waiting time (seconds): ${waiting}"
          sleep ${_sleep}
        else
          waiting=$(wait_time)
          logInfo "Build done with status: ${build_status}"
          logInfo "Build processed in ${waiting} (seconds)"
          postSeriesMetric "concourse.measure.merge.build.duration" ${waiting}
        fi
      fi
    done
}


# main app
cloneRepoAndMergePrBranchToBase
getMergeCommit
pollVersions
