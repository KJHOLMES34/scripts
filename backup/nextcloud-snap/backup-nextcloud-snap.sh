#!/usr/bin/env bash
# shellcheck disable=2181

if [[ "${VERBOSE:-0}" == "4" ]]; then
    set -x
fi

set -euo pipefail

readonly MAX_ARCHIVE_SIZE="${MAX_ARCHIVE_SIZE:-$((1024**4))}"  # Size in KiB

debug() {
    echo "${@}" 1>&2
}

fail() {
    echo "FAILURE: ${1:-exiting}" 1>&2
    exit "${2:-1}"
}

if [[ -z ${DEBUG+x} ]]; then
    if [ "$EUID" -ne 0 ]; then
        fail "Please run as root"
    fi
fi

if [[ -z "${1}" ]]; then
    debug "USAGE:"
    debug "  ${0} /path/to/storage/location"
    exit
fi

readonly TARGET_BACKUP_DIR="${1/%\/}"  # Remove trailing /
if [[ -n ${VERBOSE+x} ]]; then echo "${TARGET_BACKUP_DIR@A}"; fi

if [[ -n ${VERBOSE+x} ]]; then echo "Backup started …"; fi
if [[ -n ${DEBUG+x} ]]; then
    readonly NC_EXPORT="Successfully exported /var/snap/nextcloud/common/backups/20220720-194312"
else
    if [[ -z ${VERBOSE+x} ]]; then
        MUTE="2> /dev/null"
        readonly MUTE
    fi
    NC_EXPORT="$(nextcloud.export "${MUTE:-}" | grep "Successfully exported")"
    readonly NC_EXPORT
fi
if [[ "${VERBOSE}" == "2" ]]; then echo "${NC_EXPORT@A}"; fi

if [[ $? -eq 0 ]]; then
    if [[ -n ${VERBOSE+x} ]]; then echo "Backup finished with exit code ${?}"; fi

    NC_BACKUP_PATH="$(echo "${NC_EXPORT}" | awk '{ print $(NF) }')"
    readonly NC_BACKUP_PATH
    if [[ "${VERBOSE}" == "2" ]]; then echo "${NC_BACKUP_PATH@A}"; fi

    NC_BACKUP_DIR="$(dirname "${NC_BACKUP_PATH}")"
    readonly NC_BACKUP_DIR
    if [[ "${VERBOSE}" == "2" ]]; then echo "${NC_BACKUP_DIR@A}"; fi

    BACKUP_NAME="$(basename "${NC_EXPORT}")"
    readonly BACKUP_NAME
    if [[ "${VERBOSE}" == "2" ]]; then echo "${BACKUP_NAME@A}"; fi

else
    fail "Backup finished with exit code ${?}" $?
fi

if [[ -n ${VERBOSE+x} ]]; then echo "Exporting backup …"; fi
if [[ "${VERBOSE}" == "3" ]]; then
    # shellcheck disable=SC2034
    readonly TAR_VERBOSE="--verbose"
fi
# Using `${NC_BACKUP_DIR:1}` removes the leading slash, making the path
# relative. That, together with `-C /`, surpresses an warning print from tar
# shellcheck disable=SC2016
TAR_CMD='tar "${TAR_VERBOSE:-}" -cz -f "${TARGET_BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C / "${NC_BACKUP_PATH:1}"'
if [[ -n ${DEBUG+x} ]]; then
    # shellcheck disable=SC2005
    echo "$(eval echo "${TAR_CMD}")"
else
    eval "${TAR_CMD}"
fi

if [[ ! $? -eq 0 ]]; then
    fail "Export failed with exit code ${?}" $?
fi
if [[ -n ${VERBOSE+x} ]]; then echo "Export complete!"; fi

if [[ -n ${VERBOSE+x} ]]; then echo "Cleaning up directory ${NC_BACKUP_PATH} …"; fi
if [[ "${VERBOSE}" == "3" ]]; then
    # shellcheck disable=SC2034
    readonly RM_VERBOSE="--verbose"
fi
# shellcheck disable=SC2016,2089
CLEANUP_CMD='rm "${RM_VERBOSE:-}" -rf "${NC_BACKUP_PATH}"'
if [[ -n ${DEBUG+x} ]]; then
    # shellcheck disable=SC2005
    echo "$(eval echo "${CLEANUP_CMD}")"
else
    eval "${CLEANUP_CMD}"
fi
if [[ -n ${VERBOSE+x} ]]; then echo "Clean-up complete!"; fi

#du -k "${TARGET_BACKUP_DIR}"
if [[ -z ${DEBUG+x} ]]; then
    if [[ "5" -ge "${MAX_ARCHIVE_SIZE}" ]]; then
        echo "WARNING: Backup archive size is greater than ${MAX_ARCHIVE_SIZE} …" 1>&2
        echo "Please check ${TARGET_BACKUP_DIR}" 1>&2
    fi
fi

