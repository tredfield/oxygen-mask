#!/bin/bash

source $(dirname $0)/add-ssh-key.sh

output=$PWD/$1
pull_request_output=$2
repo=${REPO}
github_access_token=${GITHUB_ACCESS_TOKEN}
datadog_api_key=${DATADOG_API_KEY}
versions=

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
    merge_version_found_time=$(date +%s)
    merge_version_found_duration=$((${merge_version_found_time}-${merge_start_time}))
    logWarn "Concourse found merge commit ${commit} in (seconds): ${merge_version_found_duration}"
    postSeriesMetric "concourse.measure.merge.version.found.duration" $merge_version_found_duration
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
      logWarn "No merge version found. Sleeping ${_sleep} seconds"
      sleep ${_sleep}
    fi
  done
}

pollBuildStatus() {
    build_status="pending"

    while [[ ("${build_status}" == "pending" || "${build_status}" == "started") ]]; do
      logInfo "Checking build status for commit ${commit} for pipeline ${build_pipeline} and repo ${manifest_repo}"
      version_input_to=$(curl -s ${host_name}/api/v1/teams/${team}/pipelines/${build_pipeline}/resources/git-${manifest_repo}/versions/${version_id}/input_to)
      statuses_count=$(echo $version_input_to | jq -r '. | length')

      logInfo "Status count: $statuses_count"

      if [ $statuses_count = 0 ]; then
        logWarn "No statues. Sleeping ${_sleep} seconds"
        sleep ${_sleep}
      else
        build_status=$(echo $version_input_to | jq -r '.[0].status')

        # still waiting for status?
        if [[ ("${build_status}" == "pending" || "${build_status}" == "started") ]]; then
          logWarn "Status is ${build_status}. Sleeping ${_sleep} seconds"
          sleep ${_sleep}
        else
          build_complete=$(date +%s)
          merge_to_build_finish=$((${build_complete}-${merge_start_time}))
          logInfo "Build done with status: ${build_status}"
          logInfo "Build processed in ${merge_to_build_finish} (seconds)"
          postSeriesMetric "concourse.measure.merge.build.duration" $merge_to_build_finish
        fi
      fi
    done
}


# main app
cloneRepoAndMergePrBranchToBase
pollVersions
