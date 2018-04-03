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
