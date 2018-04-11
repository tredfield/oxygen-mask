#!/bin/bash

source $(dirname $0)/add-ssh-key.sh

do_merge=${DO_MERGE}

cloneRepoAndMergePrBranchToBase() {
  if [[ "${do_merge}" == "true" ]]; then
    branch=$(cat pull-request-output/pr_branch_name)
    base=$(cat pull-request-output/pr_base_name)

    # checkout repo and create a base branch and branch for pull-request
    logInfo "Cloning ${repo}..."
    git clone git@github.com:scpprd/${repo}.git
    cd ${repo}

    logInfo "Checking out ${base}..."
    git checkout ${base}
    git merge origin/${branch}
    git push
  fi
}

cloneRepoAndMergePrBranchToBase
