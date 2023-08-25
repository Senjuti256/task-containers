#!/usr/bin/env bats

source ./test/helper/helper.sh

declare -rx E2E_S2I_PVC_NAME="${E2E_S2I_PVC_NAME:-}"
declare -rx E2E_S2I_PVC_SUBPATH="${E2E_S2I_PVC_SUBPATH:-}"

# E2E tests parameters for the test pipeline
declare -rx E2E_S2I_PARAMS_URL="${E2E_S2I_PARAMS_URL:-}"
declare -rx E2E_S2I_PARAMS_REVISION="${E2E_S2I_PARAMS_REVISON:-}"
declare -rx E2E_S2I_PARAMS_IMAGE="${E2E_S2I_PARAMS_IMAGE:-}"
declare -rx E2E_S2I_LANGUAGE="${E2E_S2I_LANGUAGE:-}"
declare -rx E2E_S2I_IMAGE_SCRIPTS_URL="${E2E_S2I_IMAGE_SCRIPTS_URL:-}"
declare -rx E2E_S2I_PARAMS_ENV_VARS="${E2E_S2I_PARAMS_ENV_VARS:-}"

@test "[e2e] pipeline-run using s2i task" {
    [ -n "${E2E_S2I_PVC_NAME}" ]
    [ -n "${E2E_S2I_PVC_SUBPATH}" ]
    [ -n "${E2E_S2I_PARAMS_URL}" ]
    [ -n "${E2E_S2I_PARAMS_REVISION}" ]
    [ -n "${E2E_S2I_PARAMS_IMAGE}" ]
    [ -n "${E2E_S2I_IMAGE_SCRIPTS_URL}" ]
    [ -n "${E2E_PARAMS_TLS_VERIFY}" ]
    [ -n "${E2E_S2I_LANGUAGE}" ]

    # cleaning up existing resources before starting a new pipelinerun
    run kubectl delete pipelinerun --all
    assert_success

    # declareing a kustomization which picks up the s2i pipeline resource and applies the contents of
    # "patch.yaml" file, to be created next
    cat <<EOF >${BASE_DIR}/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - pipeline-s2i.yaml
patches:
  - path: patch.yaml
    target:
      kind: Pipeline
      name: task-s2i
EOF
    assert_file_exist ${BASE_DIR}/kustomization.yaml

    # patches the Tekton Pipeline to specificy which s2i language is being tested, the underlying
    # task name must be using the target language
    cat <<EOF >${BASE_DIR}/patch.yaml
---
- op: replace
  path: /metadata/name
  value: task-s2i-${E2E_S2I_LANGUAGE}
- op: replace
  path: /spec/tasks/1/name
  value: s2i-${E2E_S2I_LANGUAGE}
- op: replace
  path: /spec/tasks/1/taskRef/name
  value: s2i-${E2E_S2I_LANGUAGE}
EOF
    assert_file_exist ${BASE_DIR}/patch.yaml

    # copying the pipeline resource to the bats temporary directory, the file is altered by
    # kutomizations defined previously
    run cp -v test/e2e/resources/pipeline-s2i.yaml ${BASE_DIR}
    assert_success

    # applying all the resources on the directory with the kustomizations defined previously
    run kubectl apply --kustomize ${BASE_DIR}
    assert_success

    tkn pipeline start task-s2i-${E2E_S2I_LANGUAGE} \
        --param="URL=${E2E_S2I_PARAMS_URL}" \
        --param="IMAGE_SCRIPTS_URL=${E2E_S2I_IMAGE_SCRIPTS_URL}" \
        --param="REVISION=${E2E_S2I_PARAMS_REVISION}" \
        --param="IMAGE=${E2E_S2I_PARAMS_IMAGE}" \
        --param="TLS_VERIFY=${E2E_PARAMS_TLS_VERIFY}" \
        --param="ENV_VARS=${E2E_S2I_PARAMS_ENV_VARS}" \
        --param="VERBOSE=true" \
        --workspace="name=source,claimName=${E2E_S2I_PVC_NAME},subPath=${E2E_S2I_PVC_SUBPATH}" \
        --showlog >&3
    assert_success

    # waiting a few seconds before asserting results
    sleep 30

    # asserting the pipelinerun status, making sure all steps have been successful
    assert_tekton_resource "pipelinerun" --partial '(Failed: 0, Cancelled 0), Skipped: 0'
    # asserting the latest taskrun instance to inspect the resources against a regular expression
    assert_tekton_resource "taskrun" --regexp $'IMAGE_DIGEST=\S+.\nIMAGE_URL=\S+*'
}
