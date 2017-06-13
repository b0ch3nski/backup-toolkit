#!/usr/bin/env bash

# define console colors
RED="\e[01;31m"
GRN="\e[01;32m"
LGRN="\e[00;32m"
BLU="\e[01;34m"
YLW="\e[01;33m"
NRM="\e[00m"

# logger: $1=message $2=color | format: "[Y-m-d T.3N] message"
log() { echo -e "${2}[$(date '+%Y-%m-%d %T.%3N')] ${1}${NRM}"; }

# check if config file $1 contains only blank lines, comments and variable declarations
validate_config() {
  if egrep -vq '^$|^#|^[^ ]*=[^;]*' "${1}"; then
    log "syntax error in config file '${1}' - offending lines:\n$(egrep -vn '^$|^#|^[^ ]*=[^;]*' "${1}")" "${RED}" >&2
    exit 1
  fi
}

# check if $1 list of binaries is available
dep_check() {
  for bin in ${1}; do
    command -v ${bin} >/dev/null 2>&1 || {
    log "'${bin}' binary could not be found in your system" "${RED}" >&2
    exit 1; }
  done
}

# convert $1 unix timestamp in seconds to "Y-m-d T" format
human_time() { date -d @${1} '+%Y-%m-%d %T'; }

# calculate elapsed time since $1 unix timestamp in seconds
# and print it in human-readable days, hours, minutes and seconds format
human_time_elapsed() {
  local -r elapsed="$(( $(date +%s) - ${1} ))"
  local -r D="$(( ${elapsed} / 60 / 60 / 24 ))"
  local -r H="$(( ${elapsed} / 60 / 60 % 24 ))"
  local -r M="$(( ${elapsed} / 60 % 60 ))"
  local -r S="$(( ${elapsed} % 60 ))"
  (( ${D} > 0 )) && printf '%d days ' ${D}
  (( ${H} > 0 )) && printf '%d hours ' ${H}
  (( ${M} > 0 )) && printf '%d minutes ' ${M}
  (( ${D} > 0 || ${H} > 0 || ${M} > 0 )) && printf 'and '
  printf '%d seconds\n' ${S}
}
