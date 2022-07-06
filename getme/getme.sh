#!/usr/bin/env bash

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "USAGE:"
  echo ""
  echo "  ${0} PROGRAM [VERSION]"
  echo ""
  echo "EXAMPLES:"
  echo ""
  echo "  ${0} helmfile 0.145.0"
  echo "  ${0} helmfile latest"
  echo ""
  echo "SUPPORTED PROGRAMS:"
  echo ""
  echo "  helmfile"
  echo "  git-credential-manager"
  exit
fi

readonly PROGRAM="${1}"
readonly VERSION_NUMBER="${2:-latest}"
readonly VERSION="${VERSION_NUMBER/#v}" # Normalize v1.2.3 to 1.2.3

get_gh_release_url() {
    local -r OWNER="${1}"
    local -r REPO="${2}"
    local -r TAG="${3:-latest}"
    local -r REGEX="${4:-linux_amd64}"

    # Set RELEASE differently depending on if TAG is latest or not
    if [[ "${TAG}" != "latest" ]]; then
        RELEASE="tags/${TAG}"
    else
        RELEASE="latest"
    fi

    local -r RELEASE_JSON=$(
        curl --silent -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${OWNER}/${REPO}/releases/${RELEASE}"
    )

    jq -r "
        .assets[]
        |
        select(.name | test(\"${REGEX}\"))
        |
        .browser_download_url
    " <(echo "${RELEASE_JSON}")

}

###########################     Program selector     ###########################
# Ensure we won't prefix latest with v
if [[ "${VERSION}" == "latest" ]]; then
    readonly VERSION_PREFIX=""
else
    readonly VERSION_PREFIX="v"
fi

if [[ "${PROGRAM}" == "helmfile" ]]; then
    readonly DOWNLOAD_URL=$(
        get_gh_release_url \
            "${PROGRAM}" "${PROGRAM}" \
            "${VERSION_PREFIX}${VERSION}"
    )
    readonly PACKAGE_FORMAT="bin"
elif [[ "${PROGRAM}" == "git-credential-manager" ]]; then
    readonly DOWNLOAD_URL=$(
        get_gh_release_url \
            "GitCredentialManager" "${PROGRAM}" \
            "${VERSION_PREFIX}${VERSION}" \
            '.*gcm-linux_amd64.*.deb'
    )
    readonly PACKAGE_FORMAT="deb"
else
    echo "❌ ERROR: program ${PROGRAM} not supported."
    exit 1
fi


##########################     Download & Install     ##########################
DOWNLOAD_DIR=$(mktemp -d)

FILENAME=$(basename "${DOWNLOAD_URL}")
echo "⏳ Downloading ${PROGRAM} …"
if [[ "${FILENAME}" == *.tar.gz ]]; then
    wget -qO - "${DOWNLOAD_URL}" | tar -xzC "${DOWNLOAD_DIR}"
elif [[ "${FILENAME}" == *.deb ]]; then
    wget -qo "${DOWNLOAD_DIR}/${FILENAME}" "${DOWNLOAD_URL}"
else
    echo "ERROR: Could not download ${PROGRAM}  ¯\_(ツ)_/¯"
    echo -e "  DIR:\t\t${DOWNLOAD_DIR}"
    echo -e "  URL:\t\t${DOWNLOAD_URL}"
    echo -e "  FILENAME:\t${FILENAME}"
    exit 1
fi
echo "✅ Download complete!"

echo "⌛ Installing ${PROGRAM} …"
if [[ "${PACKAGE_FORMAT}" == "bin" ]]; then
    sudo install "${DOWNLOAD_DIR}/${PROGRAM}" /usr/local/bin
elif [[ "${PACKAGE_FORMAT}" == "deb" ]]; then
    sudo apt install "${DOWNLOAD_DIR}/${PROGRAM}.deb"
else
    echo "ERROR: Package format was ${PACKAGE_FORMAT}  ¯\_(ツ)_/¯"
    exit 1
fi
echo "😀 Installation complete!"

