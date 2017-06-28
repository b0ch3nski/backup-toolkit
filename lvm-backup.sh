#!/usr/bin/env bash
set -eo pipefail

source "${0%/*}/common.sh"

# list all volume groups that match global $INCLUDE_VG (regex)
list_volume_groups() { vgs --readonly --noheadings -o vg_name --select 'vg_name =~ '${INCLUDE_VG}'' | tr -d ' '; }

# list all logical volumes for selected volume group $1 that match global $INCLUDE_LV (regex)
list_logical_vols() { lvs --readonly --noheadings -o lv_name --select 'vg_name = '${1}' && lv_name =~ '${INCLUDE_LV}'' | tr -d ' '; }

# calculate size of snapshot volume considering free space on volume group $1, amount of volumes $2 and global $KEEP_VG_FREE limit
get_snapshot_vol_size() {
  local -r unit="k"
  local -r free="$(vgs --readonly --noheadings --units ${unit} -o vg_free --select 'vg_name = '${1}'' | tr -d ' ' | cut -d "." -f1)"
  echo "$(( (((100 - ${KEEP_VG_FREE}) * ${free}) / 100) / ${2} ))${unit}"
}

# get list of '$1/path' to exclude from backup formatted as a list of '--exclude-rx=pattern' bup index parameters
get_exclusion_params() {
  local args=() i=0
  for dir in ${EXCLUDE_DIRS}; do
    args[$i]="--exclude-rx=\"^${1}/${dir}\""
    ((++i))
  done
  echo "${args[@]}"
}

# print welcome/info message
print_info_msg() {
  echo -e \
    "${RED}lvm-backup.sh\n" \
    "${LGRN}-h|--help                        " "${NRM}Print this message\n" \
    "${LGRN}--non-interactive                " "${NRM}Skip interactive sanity check                               " "${GRN}[optional]" "${RED}${NONINTERACTIVE}\n" \
    "${LGRN}--config=<file>                  " "${NRM}Use specific configuration file                             " "${GRN}[optional]" "${RED}${CFG_FILE}\n" \
    "${LGRN}<config-file>    " "${BLU}INCLUDE_VG     " "${NRM}Include following VGs during LVs lookup (regex)             " "${YLW}[required]" "${RED}${INCLUDE_VG}\n" \
    "${LGRN}<config-file>    " "${BLU}INCLUDE_LV     " "${NRM}Include following LVs during snapshot creation phase (regex)" "${YLW}[required]" "${RED}${INCLUDE_LV}\n" \
    "${LGRN}<config-file>    " "${BLU}KEEP_VG_FREE   " "${NRM}Snapshot creation phase should leave following % of VGs free" "${GRN}[optional]" "${RED}${KEEP_VG_FREE}\n" \
    "${LGRN}<config-file>    " "${BLU}BACKUP_DIR     " "${NRM}Backup target directory (initialized Bup repository)        " "${GRN}[optional]" "${RED}${BACKUP_DIR}\n" \
    "${LGRN}<config-file>    " "${BLU}BACKUP_COMPRESS" "${NRM}Backup compression level (0-9)                              " "${GRN}[optional]" "${RED}${BACKUP_COMPRESS}\n" \
    "${LGRN}<config-file>    " "${BLU}BACKUP_FSCK    " "${NRM}Generate recovery blocks after the backup                   " "${GRN}[optional]" "${RED}${BACKUP_FSCK}\n" \
    "${LGRN}<config-file>    " "${BLU}LOW_PRIORITY   " "${NRM}Set 'nice' and 'ionice' to lowest priority levels           " "${GRN}[optional]" "${RED}${LOW_PRIORITY}\n" \
    "${LGRN}<config-file>    " "${BLU}BACKUP_STATUS  " "${NRM}Print each indexed file with it's status (A, M, D, or space)" "${GRN}[optional]" "${RED}${BACKUP_STATUS}${NRM}"
}

# parse command line arguments
for arg in "${@}"; do
  case ${arg} in
    -h|--help)
      print_info_msg
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

# validate and read config file
[[ -z "${CFG_FILE// }" || ! -f "${CFG_FILE}" ]] && CFG_FILE="${0%/*}/lvm-backup.cfg"
validate_config "${CFG_FILE}"
source "${CFG_FILE}"

# fail if required binary dependencies are missing
dep_check "lvm git bup par2"

# fail if required variables are not set
if [[ -z "${INCLUDE_VG// }" || -z "${INCLUDE_LV// }" ]]; then
  print_info_msg
  log "required variables are not set" "${RED}" >&2
  exit 1
fi

# set default values for optional variables
: "${NONINTERACTIVE:=false}"
: "${KEEP_VG_FREE:=15}"
: "${BACKUP_DIR:=$(pwd)}"
: "${BACKUP_COMPRESS:=0}"
: "${BACKUP_FSCK:=true}"
: "${LOW_PRIORITY:=false}"
: "${BACKUP_STATUS:=false}"

print_info_msg

# check if $BACKUP_DIR is a valid Git/Bup repository
if [[ "$(GIT_DIR=${BACKUP_DIR} git rev-parse >/dev/null 2>&1; echo $?)" != 0 ]]; then
  log "'${BACKUP_DIR}' is not a valid Git/Bup repository" "${RED}" >&2
  exit 1
fi

# interactive sanity check
if [[ "${NONINTERACTIVE}" = false ]]; then
  echo -en "${RED}Is that correct? Proceed? (y/n): "
  read -n 1 -r
  echo -e "${NRM}\n"
  [[ ${REPLY} =~ ^[Yy]$ ]] || exit 0
fi

readonly vol_groups="$(list_volume_groups)"
[[ -z "${vol_groups// }" ]] && { log "no VGs found matching '${INCLUDE_VG}'" "${RED}" >&2; exit 1; }

log "[phase 1] create snapshot volumes" "${RED}"
created_snapshot_vols=""
for vg in ${vol_groups}; do
  logical_vols="$(list_logical_vols ${vg})"
  [[ -z "${logical_vols// }" ]] && { log "no LVs found matching '${INCLUDE_LV}'" "${RED}" >&2; exit 1; }

  logical_vols_num="$(wc -l <<< "${logical_vols}")"
  log "volume group: ${vg} | logical volumes: ${logical_vols_num}" "${BLU}"
  snapshot_vol_size="$(get_snapshot_vol_size ${vg} ${logical_vols_num})"

  for lv in ${logical_vols}; do
    snapshot_vol_name="snap_${lv}"
    log "creating snapshot volume '${snapshot_vol_name}' of LV '${vg}/${lv}' with size '${snapshot_vol_size}'" "${GRN}"

    lvcreate -y -s -n ${snapshot_vol_name} -L ${snapshot_vol_size} ${vg}/${lv}
    created_snapshot_vols+=" ${vg}/${snapshot_vol_name}"
  done
done

# all backups should have the same time (as close as possible to snapshot creation time)
readonly timestamp="$(date +%s)"

# translate boolean variables to parameters for eval
[[ "${LOW_PRIORITY}" = true ]] && LOW_PRIORITY="nice -n19 ionice -c2 -n7" || unset LOW_PRIORITY
[[ "${BACKUP_STATUS}" = true ]] && BACKUP_STATUS="--status" || unset BACKUP_STATUS

log "[phase 2] mount, backup, umount and remove snapshot volumes" "${RED}"
for lv in ${created_snapshot_vols}; do
  # hostname-original_lv_name
  backup_name="$(hostname)-$(awk -F'_' '{ print $2 }' <<< ${lv})"
  # /mnt/vg-snapshot_lv_name
  mount_path="/mnt/$(sed 's/\//-/' <<< ${lv})"

  log "mounting '/dev/${lv}' to '${mount_path}'" "${YLW}"
  mkdir ${mount_path}
  mount -o ro /dev/${lv} ${mount_path}

  log "indexing '${mount_path}'" "${GRN}"
  eval BUP_DIR=${BACKUP_DIR} ${LOW_PRIORITY} \
    bup index --update --one-file-system --no-check-device $(get_exclusion_params ${mount_path}) ${BACKUP_STATUS} ${mount_path}

  log "backing up '${mount_path}' with name '${backup_name}' and timestamp '$(human_time ${timestamp})'" "${GRN}"
  eval BUP_DIR=${BACKUP_DIR} ${LOW_PRIORITY} \
    bup save --strip ${mount_path} --date=${timestamp} --name=${backup_name} --compress=${BACKUP_COMPRESS} ${mount_path}

  log "umounting '${mount_path}' and removing snapshot volume '${lv}'" "${YLW}"
  sync
  umount ${mount_path}
  rmdir ${mount_path}
  lvremove -y ${lv}
done

if [[ "${BACKUP_FSCK}" = true ]]; then
  log "[phase 3] generate backup recovery blocks" "${RED}"
  eval BUP_DIR=${BACKUP_DIR} ${LOW_PRIORITY} \
    bup fsck --generate --quick
fi

log "[success] backup finished" "${RED}"
log "took: $(human_time_elapsed ${timestamp})" "${BLU}"
log "backup target '${BACKUP_DIR}' size: $(du -sh ${BACKUP_DIR} | awk '{ print $1 }')" "${BLU}"
