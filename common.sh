# define available console colors
readonly RED="\e[01;31m" \
         GRN="\e[01;32m" \
         LGRN="\e[00;32m" \
         YLW="\e[01;33m" \
         BLU="\e[01;34m" \
         MGT="\e[01;35m" \
         CYA="\e[01;36m" \
         NRM="\e[00m"

# define how date should look like in logs
readonly LOG_DATE_FORMAT="+%Y-%m-%d %T.%3N"

# run config against this pattern to find out if it contains prohibited characters
readonly CFG_VALID_PATTERN="^$|^#|^[^ ]*=[^;]*"

# logger: $1=message $2=color | output format: "[date] message"
log() { echo -e "${2}[$(date "${LOG_DATE_FORMAT}")] ${1}${NRM}"; }

# parse command line arguments
parse_arguments() {
  for arg in ${@}; do
    case ${arg} in
      -h|--help)
        usage
        exit 0 ;;
      --non-interactive)
        NONINTERACTIVE="true"
        shift ;;
      --config=*)
        CFG_FILE="${arg#*=}"
        shift ;;
      *) ;; # unknown parameter passed - ignoring
    esac
  done
}

# load config file $1 if it exists (fallback to file $2) and contains only blank lines, comments and variable declarations
# otherwise print syntax error message and point at offending lines
load_config() {
  [[ -f "${1}" ]] && CFG_FILE="${1}" || CFG_FILE="${0%/*}/${2}"

  if egrep -vq "${CFG_VALID_PATTERN}" "${CFG_FILE}"; then
    log "syntax error in config file '${CFG_FILE}' - offending lines:\n$(egrep -vn "${CFG_VALID_PATTERN}" "${CFG_FILE}")" "${RED}" >&2
    exit 1
  fi
  source "${CFG_FILE}"
}

# fail when at least one variable of $1 list of variables is empty and log $2 message
fail_when_empty() {
  for var in ${1}; do
    if [[ -z "${var// }" ]]; then
      log "${2}" "${RED}" >&2
      exit 1
    fi
  done
}

# check if $1 list of binaries is available
ensure_deps() {
  for bin in ${1}; do
    command -v "${bin}" >/dev/null 2>&1 || {
    log "'${bin}' binary could not be found in your system" "${RED}" >&2
    exit 1; }
  done
}

# interactive sanity check
sanity_check() {
  if [[ "${NONINTERACTIVE}" = false ]]; then
    echo -en "${RED}Is that correct? Proceed? (y/n): "
    read -n 1 -r
    echo -e "${NRM}\n"
    [[ "${REPLY}" =~ ^[Yy]$ ]] || exit 0
  fi
}

# calculate elapsed time since $1 unix timestamp in seconds
# and print it in human-readable days, hours, minutes and seconds format
print_elapsed_time() {
  local -r elapsed="$(( $(date +%s) - ${1} ))"
  local -r D="$(( ${elapsed} / 60 / 60 / 24 ))"
  local -r H="$(( ${elapsed} / 60 / 60 % 24 ))"
  local -r M="$(( ${elapsed} / 60 % 60 ))"
  local -r S="$(( ${elapsed} % 60 ))"
  (( ${D} > 0 )) && printf "%d days " "${D}"
  (( ${H} > 0 )) && printf "%d hours " "${H}"
  (( ${M} > 0 )) && printf "%d minutes " "${M}"
  (( ${D} > 0 || ${H} > 0 || ${M} > 0 )) && printf "and "
  printf "%d seconds\n" "${S}"
}
