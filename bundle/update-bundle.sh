#!/usr/bin/env bash
# SPDX-FileCopyrightText: Yalan Zhang <yalzhang@redhat.com>
#
# SPDX-License-Identifier: CC0-1.0

set -euo pipefail

# Hardcoded image pullspecs with SHA256 digests - these will be automatically updated by Konflux component nudges
# When component builds complete, Konflux will send PRs to update these digests
# IMPORTANT: Must use @sha256: format, NOT tags - Konflux only updates digest references

export OPERATOR_IMAGE="registry.redhat.io/confidential-clusters-beta/confidential-cluster-rhel9-operator@sha256:dc8e8d6f9d47a75f486fcc6d304d53c223752ebeb0f16f8111e8762c8037e0a4"
export COMPUTE_PCRS_IMAGE="registry.redhat.io/confidential-clusters-beta/compute-pcrs-rhel9@sha256:7056c8887b7cb6fbfdaef0394a5cd64e23a7ee7afa36ba1038455de4de96fd9a"
export REG_SERVER_IMAGE="registry.redhat.io/confidential-clusters-beta/registration-server-rhel9@sha256:81b5455da8609ad3a34160ae864db64f12fa899e244001bf9bd6a4591a228e33"
export ATTESTATION_KEY_REGISTER_IMAGE="registry.redhat.io/confidential-clusters-beta/attestation-key-register-rhel9@sha256:cd7ff8aa957cede1839ff2a405158d1b5f06bb5f09ec368920af3994dccca713"
export TRUSTEE_IMAGE="registry.redhat.io/build-of-trustee/trustee-rhel9@sha256:badc4d357d15c495d695fd84736ebdffdad4b9fb3ec89c40c9b47a1c2b3a9d41"

# These are passed in from the Containerfile build args
: "${TAG:?TAG must be set}"
# NAMESPACE is optional - upstream Makefile has default (trusted-execution-clusters)
# This is only used during manifest generation and is removed from RBAC bindings
# The final bundle is namespace-agnostic and can be installed anywhere
: "${NAMESPACE:=trusted-execution-clusters}"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "${SCRIPT_DIR}/..")

echo "=> Building bundle with the following images:"
echo "   OPERATOR_IMAGE=${OPERATOR_IMAGE}"
echo "   COMPUTE_PCRS_IMAGE=${COMPUTE_PCRS_IMAGE}"
echo "   REG_SERVER_IMAGE=${REG_SERVER_IMAGE}"
echo "   ATTESTATION_KEY_REGISTER_IMAGE=${ATTESTATION_KEY_REGISTER_IMAGE}"
echo "   TRUSTEE_IMAGE=${TRUSTEE_IMAGE}"
echo "   TAG=${TAG}"
echo "   NAMESPACE=${NAMESPACE}"
echo ""

# Extract REGISTRY from OPERATOR_IMAGE (everything before the last /)
export REGISTRY="${OPERATOR_IMAGE%/*}"

# Generate manifests first (creates CRDs and RBAC rules)
echo "=> Generating manifests..."
make -C "${PROJECT_ROOT}/operator" manifests \
    NAMESPACE="${NAMESPACE}" \
    REGISTRY="${REGISTRY}" \
    TAG="${TAG}"

# Generate bundle using the Makefile
# The Makefile will:
# - Copy CRDs from config/crd/
# - Copy RBAC from config/rbac/
# - Inject RBAC rules into CSV
# - Patch image references with the hardcoded images above
# - Validate the bundle with operator-sdk
echo "=> Generating bundle..."
cd "${PROJECT_ROOT}/operator" && \
    make bundle \
    TAG="${TAG}" \
    NAMESPACE="${NAMESPACE}" \
    REGISTRY="${REGISTRY}" \
    OPERATOR_IMAGE="${OPERATOR_IMAGE}" \
    COMPUTE_PCRS_IMAGE="${COMPUTE_PCRS_IMAGE}" \
    REG_SERVER_IMAGE="${REG_SERVER_IMAGE}" \
    ATTESTATION_KEY_REGISTER_IMAGE="${ATTESTATION_KEY_REGISTER_IMAGE}" \
    TRUSTEE_IMAGE="${TRUSTEE_IMAGE}"

# Apply downstream-specific customizations to the generated bundle
echo "=> Applying downstream customizations..."
bash "${PROJECT_ROOT}/bundle/customize-bundle.sh"

echo "=> Bundle generation complete!"
