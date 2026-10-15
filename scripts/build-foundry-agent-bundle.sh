#!/usr/bin/env bash

# Builds the Linux dependency directory required by Foundry's bundled Python
# code-deployment mode, using only the approved Microsoft package proxy.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly AGENT_DIR="${REPO_ROOT}/litellm-deepwiki-agent/src/litellm-deepwiki-agent"
readonly PACKAGES_DIR="${AGENT_DIR}/packages"
readonly APPROVED_INDEX="https://packagefeedproxy.microsoft.io/pypi/simple"

if ! command -v uv >/dev/null 2>&1; then
    printf 'Error: uv is required but was not found on PATH.\n' >&2
    exit 1
fi

cd "${AGENT_DIR}"

# Export production dependencies from the reviewed lockfile. The generated
# requirements file is shipped as deployment provenance, not re-resolved.
UV_DEFAULT_INDEX="${APPROVED_INDEX}" \
    uv export \
    --frozen \
    --no-dev \
    --no-emit-project \
    --format requirements.txt \
    --output-file requirements.txt

# This path is fixed and guarded before cleanup so the script cannot remove a
# caller-selected directory.
if [[ "${PACKAGES_DIR}" != "${AGENT_DIR}/packages" ]]; then
    printf 'Error: unexpected packages directory.\n' >&2
    exit 1
fi
rm -rf "${PACKAGES_DIR}"

# Download and extract CPython 3.13 Linux wheels. Foundry adds packages/ to the
# runtime import path in bundled mode; source builds are intentionally disabled.
UV_DEFAULT_INDEX="${APPROVED_INDEX}" \
    uv pip install \
    --requirements requirements.txt \
    --target "${PACKAGES_DIR}" \
    --python-version 3.13 \
    --python-platform x86_64-manylinux2014 \
    --only-binary :all:

printf 'Built Foundry dependency bundle at %s\n' "${PACKAGES_DIR}"
