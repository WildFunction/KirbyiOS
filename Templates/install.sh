#!/bin/bash
# Installs the WildFunction Xcode file templates for the current user, replacing older copies.
# Then use File > New > File from Template… in Xcode and find the "WildFunction" group.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/Library/Developer/Xcode/Templates/File Templates/WildFunction"
TEMPLATE_NAME="WildFunction Page.xctemplate"

if [[ ! -d "${SOURCE_DIR}/${TEMPLATE_NAME}" ]]; then
    echo "error: template not found at ${SOURCE_DIR}/${TEMPLATE_NAME}" >&2
    exit 1
fi

mkdir -p "${TARGET_DIR}"
rm -rf "${TARGET_DIR:?}/${TEMPLATE_NAME}"
cp -R "${SOURCE_DIR}/${TEMPLATE_NAME}" "${TARGET_DIR}/"

echo "Installed: ${TARGET_DIR}/${TEMPLATE_NAME}"
echo "Restart Xcode if it is running."
