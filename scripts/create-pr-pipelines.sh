#!/bin/bash

target=$1
concourse_target_url=$2
check_interval=$3
scripts=$(dirname $0)

# generate pipeline
gotpl ${scripts}/../pull-request-metrics.yml < ${scripts}/../repos.yml > /tmp/pull-request-metrics.yml

# set pipeline
fly -t ${target} sp -p pull-request-metric -c /tmp/pull-request-metrics.yml --var="concourse_target_url=${concourse_target_url}" --var="check_interval=${check_interval}"
