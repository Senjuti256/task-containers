#!/usr/bin/env bats

source ./test/helper/helper.sh

# E2E tests parameters for the test pipeline
readonly E2E_PARAM_PATH_CONTEXT="${E2E_PARAM_PATH_CONTEXT:-.}"
readonly E2E_PVC_NAME="${E2E_PVC_NAME:-}"

# Spinning up a PipelineRun using the S2I Go Task to build and push a container image
@test "[e2e] pipeline-run using s2i-go task" {
  # Asserting required configuration is informed
  [ -n "${E2E_PARAM_PATH_CONTEXT}" ]
  [ -n "${E2E_PVC_NAME}" ]


  # Cleaning up existing resources before starting a new pipelinerun
  run kubectl delete pipelinerun --all
  assert_success

  # E2E PipelineRun
  run tkn pipeline start s2i-go-tr \
    --param="PATH_CONTEXT=${E2E_PARAM_PATH_CONTEXT}" \
    --workspace="name=source,claimName=${E2E_PVC_NAME},subPath=source" \
    --filename=test/e2e/resources/10-pipeline.yaml \
    --showlog >&3
  assert_success

  # Waiting a few seconds before asserting results
  sleep 15

  #
  # Asserting PipelineRun Status
  #


  # Asserting Status
  readonly tmpl_file="${BASE_DIR}/go-template.tpl"

  cat >${tmpl_file} <<EOS
{{- range .status.conditions -}}
  {{- if and (eq .type "Succeeded") (eq .status "True") }}
    {{ .message }}
  {{- end }}
{{- end -}}
EOS

  # Using template to select the required information and asserting the task has succeeded
  run tkn pipelinerun describe --output=go-template-file --template=${tmpl_file}
  assert_success
  assert_output --partial '(Failed: 0, Cancelled 0), Skipped: 0'

  # Asserting Results
  cat >${tmpl_file} <<EOS
{{- range .status.taskResults -}}
    {{ printf "%s=%s\n" .name .value }}
{{- end -}}
EOS

  # Using a template to render the result attributes on a multi-line key-value pair output
  run tkn pipelinerun describe --output=go-template-file --template=${tmpl_file}
  assert_success
  
}