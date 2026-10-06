#!/bin/bash
# Generates a page from the same templates on the command line, without Xcode.
#
#   Templates/new-page.sh DemoDetail                 # creates DemoDetail/ in the current directory
#   Templates/new-page.sh DemoList --list            # list page
#   Templates/new-page.sh DemoDetail --output Sources/App/Pages
set -euo pipefail

usage() {
    echo "usage: $(basename "$0") <PageName> [--list] [--output <dir>]" >&2
    exit 1
}

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SOURCE_DIR}/WildFunction Page.xctemplate"
PLACEHOLDER="___VARIABLE_productName:identifier___"
FILE_PLACEHOLDER="___FILEBASENAME___"

NAME=""
VARIANT="Swift"
OUTPUT_DIR="$(pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list) VARIANT="ListSwift"; shift ;;
        --output) [[ $# -ge 2 ]] || usage; OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) echo "error: unknown option $1" >&2; usage ;;
        *) [[ -z "${NAME}" ]] || usage; NAME="$1"; shift ;;
    esac
done

[[ -n "${NAME}" ]] || usage
if [[ ! "${NAME}" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
    echo "error: page name must be an UpperCamelCase identifier, got '${NAME}'" >&2
    exit 1
fi

DESTINATION="${OUTPUT_DIR}/${NAME}"
if [[ -e "${DESTINATION}" ]]; then
    echo "error: ${DESTINATION} already exists" >&2
    exit 1
fi

mkdir -p "${DESTINATION}"
for template in "${TEMPLATE_DIR}/${VARIANT}"/*.swift; do
    file_name="$(basename "${template}")"
    target="${DESTINATION}/${file_name/${FILE_PLACEHOLDER}/${NAME}}"
    sed "s/${PLACEHOLDER}/${NAME}/g" "${template}" > "${target}"
    echo "Created ${target}"
done
