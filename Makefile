# using the chart name and version from chart's metadata
CHART_NAME ?= $(shell awk '/^name:/ { print $$2 }' Chart.yaml)
CHART_VERSION ?= $(shell awk '/^version:/ { print $$2 }' Chart.yaml)

# bats entry point and default flags
BATS_CORE = ./test/.bats/bats-core/bin/bats
BATS_FLAGS ?= --print-output-on-failure --show-output-of-passing-tests --verbose-run

# path to the bats test files, overwite the variables below to tweak the test scope
E2E_TEST_DIR ?= ./test/e2e
# based on the test directory, selecting all dot-bats files
E2E_TESTS ?= $(E2E_TEST_DIR)/*.bats

# external task dependency to run the end-to-end tests pipeline
TASK_GIT ?= https://github.com/openshift-pipelines/task-git/releases/download/0.0.1/task-git-0.0.1.yaml

# container registry URL, usually hostname and port
REGISTRY_URL ?= registry.registry.svc.cluster.local:32222
# container registry namespace, as in the section of the registry allowed to push images
REGISTRY_NAMESPACE ?= task-containers
# base part of a fully qualified container image name
IMAGE_BASE ?= $(REGISTRY_URL)/$(REGISTRY_NAMESPACE)

# skopeo-copy task e2e test variables, source, destination url and tls-verify parameter.
E2E_SC_PARAMS_SOURCE ?= docker://docker.io/library/busybox:latest
# end-to-end test destination image name and tag
E2E_SC_IMAGE_TAG ?= busybox:latest
# end-to-end test fully qualified destination image name
E2E_SC_PARAMS_DESTINATION ?= docker://$(IMAGE_BASE)/${E2E_SC_IMAGE_TAG}

# setting tls-verify as false disables the HTTPS client as well, something we need for e2e testing
# using the internal container registry (HTTP based)
E2E_PARAMS_TLS_VERIFY ?= false

# workspace "source" pvc resource and name
E2E_BUILDAH_PVC ?= test/e2e/resources/pvc-buildah.yaml
E2E_BUILDAH_PVC_NAME ?= task-buildah

# workspace "source" pvc resource and name for s2i task tests
E2E_S2I_PVC ?= test/e2e/resources/pvc-s2i.yaml
E2E_S2I_PVC_NAME ?= task-s2i
E2E_S2I_PVC_SUBPATH ?= source

# auxiliary task to create a Containerfile for buildah end-to-end testing
E2E_BUILDAH_TASK_CONTAINERFILE_STUB ?= test/e2e/resources/task-containerfile-stub.yaml
# container image name and tag to be created by buildah during e2e
E2E_BUILDAH_IMAGE_TAG ?= task-buildah:latest
# fully qualified container image passed to buildah task IMAGE param
E2E_BUILDAH_PARAMS_IMAGE ?= $(IMAGE_BASE)/${E2E_BUILDAH_IMAGE_TAG}

# container image name and tag to be created by s2i during e2e
E2E_S2I_IMAGE_TAG ?= task-s2i:latest
# (fully qualified) container image passed to s2i task IMAGE param
E2E_S2I_PARAMS_IMAGE ?= $(IMAGE_BASE)/${E2E_S2I_IMAGE_TAG}

# s2i end-to-end test pipeline params, the git repository URL and revision
E2E_S2I_PARAMS_URL ?= https://github.com/cpuguy83/go-md2man.git
E2E_S2I_PARAMS_REVISION ?= master

# s2i end-to-end test language of choice for using correct builder image
E2E_S2I_LANGUAGE ?= python

# s2i's "image-script-url" flag for container-file generation
E2E_S2I_IMAGE_SCRIPTS_URL ?= image:///usr/libexec/s2i

# s2i end-to-end test pipeline params adding env variables as a comma-separated string
E2E_S2I_PARAMS_ENV_VARS ?= 

# path to the github actions testing workflows
ACT_WORKFLOWS ?= ./.github/workflows/test.yaml

# generic arguments employed on most of the targets
ARGS ?=

# making sure the variables declared in the Makefile are exported to the executables/scripts invoked
# on all targets
.EXPORT_ALL_VARIABLES:

# uses helm to render the resource templates to the stdout
define render-template
	@helm template $(ARGS) .
endef

# renders the task resource file printing it out on the standard output
helm-template:
	$(call render-template)

default: helm-template

# renders and installs the resources (task)
install:
	$(call render-template) |kubectl $(ARGS) apply -f -

# removes the package helm chart, and also the chart-releaser temporary directories
clean:
	rm -f $(CHART_NAME)-*.tgz >/dev/null 2>&1 || true

# packages the helm-chart as a single tarball, using it's name and version to compose the file
helm-package: clean
	helm package $(ARGS) .
	tar -ztvpf $(CHART_NAME)-$(CHART_VERSION).tgz

# installs "git" task directly from the informed location, the task is required to run the test-e2e
# target, it will hold the "source" workspace data
.PHONY: task-git
task-git:
	kubectl apply -f $(TASK_GIT)

# prepares the buildah end-to-end tests, installs the required resources
.PHONY: prepare-e2e-buildah
prepare-e2e-buildah: task-git
	kubectl apply -f $(E2E_BUILDAH_TASK_CONTAINERFILE_STUB)
	kubectl apply -f $(E2E_BUILDAH_PVC)

# prepares the s2i end-to-end tests, installs the required resources
.PHONY: prepare-e2e-s2i
prepare-e2e-s2i: task-git
	kubectl apply -f $(E2E_S2I_PVC)

# runs bats-core against the pre-determined tests
.PHONY: bats
bats: install
	$(BATS_CORE) $(BATS_FLAGS) $(ARGS) $(E2E_TESTS)

# runs the end-to-end tests narrowing down on "skopeo-copy"
.PHONY: test-e2e-skopeo-copy
test-e2e-skopeo-copy: E2E_TESTS = $(E2E_TEST_DIR)/*skopeo-copy*.bats
test-e2e-skopeo-copy: bats

# runs the end-to-end tests for buildah
.PHONY: test-e2e-buildah
test-e2e-buildah: prepare-e2e-buildah
test-e2e-buildah: E2E_TESTS = $(E2E_TEST_DIR)/*buildah*.bats
test-e2e-buildah: bats

# runs the end-to-end tests for s2i-python
.PHONY: test-e2e-s2i-python
test-e2e-s2i-python: prepare-e2e-s2i
test-e2e-s2i-python: E2E_S2I_LANGUAGE = python
test-e2e-s2i-python: E2E_S2I_IMAGE_TAG = task-s2i-python:latest
test-e2e-s2i-python: E2E_S2I_PARAMS_URL = https://github.com/Kalebu/Plagiarism-checker-Python
test-e2e-s2i-python: test-e2e-s2i

# runs the end-to-end tests for s2i-ruby
.PHONY: test-e2e-s2i-ruby
test-e2e-s2i-ruby: prepare-e2e-s2i
test-e2e-s2i-ruby: E2E_S2I_LANGUAGE = ruby
test-e2e-s2i-ruby: E2E_S2I_IMAGE_TAG = task-s2i-ruby:latest
test-e2e-s2i-ruby: E2E_S2I_PARAMS_URL = https://github.com/DataDog/dd-trace-rb
test-e2e-s2i-ruby: test-e2e-s2i

# runs the end-to-end tests for s2i-perl
.PHONY: test-e2e-s2i-perl
test-e2e-s2i-perl: prepare-e2e-s2i
test-e2e-s2i-perl: E2E_S2I_LANGUAGE = perl
test-e2e-s2i-perl: E2E_S2I_IMAGE_TAG = task-s2i-perl:latest
test-e2e-s2i-perl: E2E_S2I_PARAMS_URL = https://github.com/major/MySQLTuner-perl
test-e2e-s2i-perl: test-e2e-s2i

# runs the end-to-end tests for s2i-php
.PHONY: test-e2e-s2i-php
test-e2e-s2i-php: prepare-e2e-s2i
test-e2e-s2i-php: E2E_S2I_LANGUAGE = php
test-e2e-s2i-php: E2E_S2I_IMAGE_TAG = task-s2i-php:latest
test-e2e-s2i-php: E2E_S2I_PARAMS_URL = https://github.com/PuneethReddyHC/online-shopping-system-advanced
test-e2e-s2i-php: test-e2e-s2i

# runs the end-to-end tests for s2i-golang
.PHONY: test-e2e-s2i-go
test-e2e-s2i-go: prepare-e2e-s2i
test-e2e-s2i-go: E2E_S2I_LANGUAGE = go
test-e2e-s2i-go: E2E_S2I_IMAGE_TAG = task-s2i-go:latest
test-e2e-s2i-go: E2E_S2I_PARAMS_URL = https://github.com/cpuguy83/go-md2man.git
test-e2e-s2i-go: test-e2e-s2i

# runs the end-to-end tests for s2i-nodejs
.PHONY: test-e2e-s2i-nodejs
test-e2e-s2i-nodejs: prepare-e2e-s2i
test-e2e-s2i-nodejs: E2E_S2I_LANGUAGE = nodejs
test-e2e-s2i-nodejs: E2E_S2I_IMAGE_TAG = task-s2i-nodejs:latest
test-e2e-s2i-nodejs: E2E_S2I_PARAMS_URL = https://github.com/ashadnasim52/sentiment-analysis
test-e2e-s2i-nodejs: test-e2e-s2i

# runs the end-to-end tests for s2i-dotnet
.PHONY: test-e2e-s2i-dotnet
test-e2e-s2i-dotnet: prepare-e2e-s2i
test-e2e-s2i-dotnet: E2E_S2I_LANGUAGE = dotnet
test-e2e-s2i-dotnet: E2E_S2I_IMAGE_TAG = task-s2i-dotnet:latest
test-e2e-s2i-dotnet: E2E_S2I_PARAMS_URL = https://github.com/biswajitpanday/CleanArchitecture.Net6.git
test-e2e-s2i-dotnet: E2E_S2I_PARAMS_REVISION = main
test-e2e-s2i-dotnet: E2E_S2I_PARAMS_ENV_VARS = DOTNET_STARTUP_PROJECT=CleanArchitecture.Api/CleanArchitecture.Api.csproj
test-e2e-s2i-dotnet: test-e2e-s2i

# runs the end-to-end tests for s2i
.PHONY: test-e2e-s2i
test-e2e-s2i: prepare-e2e-s2i
test-e2e-s2i: E2E_TESTS = $(E2E_TEST_DIR)/*s2i*.bats
test-e2e-s2i: bats

# runs all the end-to-end tests against the current kubernetes context, it will required a cluster
# with Tekton Pipelines (OpenShift Pipelines) and a container registry instance
.PHONY: test-e2e
test-e2e: prepare-e2e-buildah
test-e2e: prepare-e2e-s2i
test-e2e: bats

# act runs the github actions workflows, so by default only running the test workflow (integration
# and end-to-end) to avoid running the release workflow accidentally
act: ARGS = --rm
act:
	act --workflows=$(ACT_WORKFLOWS) $(ARGS)
