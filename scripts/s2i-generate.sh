#!/usr/bin/env bash
#
# Uses s2i to generate the repesctive Containerfile based on the infomred builder. The Containerfile
# is stored on a temporary location.
#

shopt -s inherit_errexit
set -eu -o pipefail

source "$(dirname ${BASH_SOURCE[0]})/common.sh"
source "$(dirname ${BASH_SOURCE[0]})/s2i-common.sh"

# s2i builder image name (fully qualified)
declare -rx S2I_BUILDER_IMAGE="${S2I_BUILDER_IMAGE:-}"

# takes the values in argument ENV_VARS and creates an array using those values
declare -ra ENV_VARS=(${@})

# re-using the same parameters than buildah, s2i needs buildah abilities to create the final
# container image based on what s2i generates
source "$(dirname ${BASH_SOURCE[0]})/buildah-common.sh"

#
# Prepare
#

# making sure the required workspace "source" is bounded, which means its volume is currently mounted
# and ready to use
phase "Inspecting source workspace '${WORKSPACES_SOURCE_PATH}' (PWD='${PWD}')"
[[ "${WORKSPACES_SOURCE_BOUND}" != "true" ]] &&
    fail "Workspace 'source' is not bounded"

phase "Inspecting context subdirectory '${PARAMS_SUBDIRECTORY}'"
[[ ! -d "${PARAMS_SUBDIRECTORY}" ]] &&
    fail "Application source code directory not found at '${PARAMS_SUBDIRECTORY}'"

phase "Adding the environment variables to '${S2I_ENVIRONMENT_FILE}'"

# add the environment variables that are sent as command line arguments from ENV_VARS parameter
touch "${S2I_ENVIRONMENT_FILE}"
if [ ${#ENV_VARS[@]} -gt 0 ]; then
    for env_var in "${ENV_VARS[@]}"; do
        echo "${env_var}" >> "${S2I_ENVIRONMENT_FILE}"
    done
fi

#
# S2I Generate
#

phase "Generating the Containerfile for S2I builder image '${S2I_BUILDER_IMAGE}'"
s2i --loglevel "${S2I_LOGLEVEL}" \
    build "${PARAMS_SUBDIRECTORY}" "${S2I_BUILDER_IMAGE}" \
        --image-scripts-url "${PARAMS_IMAGE_SCRIPTS_URL}" \
        --as-dockerfile "${S2I_CONTAINERFILE_PATH}" \
        --environment-file "${S2I_ENVIRONMENT_FILE}"

phase "Inspecting the Containerfile generated at '${S2I_CONTAINERFILE_PATH}'"
[[ ! -f "${S2I_CONTAINERFILE_PATH}" ]] &&
    fail "Generated Containerfile is not found!"

set +x
phase "Generated Containerfile payload"
echo -en ">>> ${S2I_CONTAINERFILE_PATH}\n$(cat ${S2I_CONTAINERFILE_PATH})\n<<< EOF\n"
