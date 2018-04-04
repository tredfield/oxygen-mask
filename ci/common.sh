#!/bin/bash

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
  host_name=$3
  tag=$4
  currenttime=$(date +%s)

  logInfo "Posting metric ${metric_name} with value ${metric_value} for host ${host_name} and tags ${tag}"
  curl -s -X POST -H "Content-type: application/json" \
  -d "{ \"series\" :
           [{\"metric\":\"$metric_name\",
            \"points\":[[$currenttime, $metric_value]]}]
  }" \
  "https://api.datadoghq.com/api/v1/series?api_key=$datadog_api_key"
}
