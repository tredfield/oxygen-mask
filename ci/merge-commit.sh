#!/bin/bash

source $(dirname $0)/add-ssh-key.sh

output=$PWD/$1
pull_request_output=$2
repo=${REPO}
github_access_token=${GITHUB_ACCESS_TOKEN}
datadog_api_key=${DATADOG_API_KEY}
versions=

wait_time() {
  current_time=$(date +%s)
  wait_time=$((${current_time}-${merge_start_time}))
  echo "$wait_time"
}

cloneRepoAndMergePrBranchToBase() {
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
  merge_start_time=$(date +%s)
  commit=$(git rev-parse HEAD)
  echo ${commit} > ${output}/commit_sha
}

getVersions() {
  # get concourse versions and see if has PR
  versions=$(curl -s ${host_name}/api/v1/teams/${team}/pipelines/${build_pipeline}/resources/git-${manifest_repo}/versions)
  version_id=$(echo $versions | jq -r --arg commit "$commit" '.[] | select(.version.ref == $commit) | .id')

  if [ -n "$version_id" ]; then
    waiting=$(wait_time)
    logWarn "Concourse found merge commit ${commit} in (seconds): ${waiting}"
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
      logWarn "No merge version found. Sleeping ${_sleep} seconds. Total waiting time (seconds): ${waiting}"
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
      logInfo "Checking build status for commit ${commit} for pipeline ${build_pipeline} and repo ${manifest_repo}"
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
pollVersions
