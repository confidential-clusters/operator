# based on ./operator/Containerfile
# SPDX-FileCopyrightText: Alice Frosi <afrosi@redhat.com>
# SPDX-FileCopyrightText: Jakob Naucke <jnaucke@redhat.com>
# SPDX-FileCopyrightText: Yair Podemsky <ypodemsk@redhat.com>
#
# SPDX-License-Identifier: CC0-1.0

ARG build_type=release
ARG build_target=operator
ARG deployment_base=registry.access.redhat.com/ubi9/ubi-minimal

FROM quay.io/konflux-ci/operator-sdk-builder:latest AS operator-sdk

# Unified builder stage, compiles all binaries in a single cargo invocation.
FROM registry.redhat.io/confidential-clusters-beta/buildroot-rhel9@sha256:84c4e5a2bb4f761d77dee1bc51894c1d43449b4f3d4b54f2fb784f90d3bc821f AS builder
LABEL project=trusted-cluster-operator
ARG build_type
WORKDIR /build

# Drift detection - ensure local build matches upstream
COPY drift-detection/detector.sh /detector.sh
COPY drift-cache /drift-cache
WORKDIR /tmp
COPY operator/Containerfile .
RUN /detector.sh ./Containerfile /drift-cache/Containerfile

WORKDIR /build
COPY operator/Makefile operator/Cargo.toml operator/Cargo.lock operator/go.mod operator/go.sum ./

# cachi2/hermeto injects the vendored-sources cargo config at operator/.cargo during the
# prefetch step. The build flattens operator/ into /build, so copy the config here too;
# without it, offline (hermetic) `cargo build`/`cargo install` can't resolve the vendored
# crates (incl. the git deps) and the build fails.
COPY operator/.cargo .cargo

COPY operator/api api
COPY operator/lib lib

# Copy Cargo.toml and lib.rs stubs for dependency pre-build caching.
COPY operator/operator/Cargo.toml operator/
COPY operator/operator/src/lib.rs operator/src/
COPY operator/compute-pcrs/Cargo.toml compute-pcrs/
COPY operator/compute-pcrs/src/lib.rs compute-pcrs/src/
COPY operator/register-server/Cargo.toml register-server/
COPY operator/register-server/src/lib.rs register-server/src/
COPY operator/attestation-key-register/Cargo.toml attestation-key-register/
COPY operator/attestation-key-register/src/lib.rs attestation-key-register/src/

RUN sed -i 's/members = .*/members = ["lib", "operator", "compute-pcrs", "register-server", "attestation-key-register"]/' Cargo.toml && \
    sed -i '/\[dev-dependencies\]/,$d' operator/Cargo.toml && \
    sed -i '/\[dev-dependencies\]/,$d' register-server/Cargo.toml && \
    sed -i '/trusted-cluster-operator-test-utils/d' lib/Cargo.toml

# Copy controller-gen from the Konflux operator-sdk builder image. The upstream
# Makefile expects the v0.20.1 filename from go.mod.
RUN mkdir -p /build/bin
COPY --from=operator-sdk /bin/controller-gen /build/bin/controller-gen-v0.20.1

# Build pinned kopium source using dependencies fetched by Hermeto. Keep kopium's
# injected .cargo/config.toml with its sources so Cargo uses the vendored crates.
COPY tools/kopium /build-tools/kopium
RUN cd /build-tools/kopium && \
    cargo build --release --locked --offline && \
    cp target/release/kopium /build/bin/kopium-0.23.0

RUN make crds-rs

# In debug builds, pre-build dependencies to avoid full rebuild on source changes.
RUN if [ "$build_type" = debug ]; then \
      cargo build -p operator -p compute-pcrs -p register-server -p attestation-key-register; \
    fi

COPY operator/operator/src operator/src
COPY operator/compute-pcrs/src compute-pcrs/src
COPY operator/register-server/src register-server/src
COPY operator/attestation-key-register/src attestation-key-register/src

RUN release_flag="" && \
    if [ "$build_type" = release ]; then release_flag="--release"; fi && \
    cargo build \
      -p operator \
      -p compute-pcrs \
      -p register-server \
      -p attestation-key-register \
      $release_flag

RUN profile_dir="debug" && \
    if [ "$build_type" = release ]; then profile_dir="release"; fi && \
    mkdir -p /output && \
    cp /build/target/${profile_dir}/operator /output/ && \
    cp /build/target/${profile_dir}/compute-pcrs /output/ && \
    cp /build/target/${profile_dir}/register-server /output/ && \
    cp /build/target/${profile_dir}/attestation-key-register /output/

# Distribution stages
FROM ${deployment_base} AS operator
COPY --from=builder /output/operator /usr/bin

# Red Hat labels
LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/confidential-cluster-rhel9-operator" \
      cpe="cpe:/a:redhat:confidential_cluster_operator:4.21::el9" \
      version="0.2.1" \
      release="1" \
      description="confidential cluster operator - manages confidential computing resources on OpenShift" \
      io.k8s.description="Kubernetes operator for managing confidential clusters with trusted execution environments" \
      url="https://github.com/confidential-clusters/operator" \
      vcs-type="git" \
      vcs-ref="" \
      distribution-scope="public" \
      com.redhat.component="confidential-cluster-operator"

ENTRYPOINT ["/usr/bin/operator"]

FROM ${deployment_base} AS attestation-key-register
COPY --from=builder /output/attestation-key-register /usr/bin

LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/attestation-key-register-rhel9" \
      cpe="cpe:/a:redhat:confidential_cluster_operator:4.21::el9" \
      version="0.2.1" \
      release="1" \
      description="Attestation key registration tool for confidential cluster operator" \
      io.k8s.description="Service for registering and managing attestation keys for confidential workloads" \
      url="https://github.com/confidential-clusters/operator" \
      vcs-type="git" \
      vcs-ref="" \
      distribution-scope="public" \
      com.redhat.component="confidential-cluster-operator-attestation-key-register"

EXPOSE 8001
ENTRYPOINT ["/usr/bin/attestation-key-register"]

FROM ${deployment_base} AS register-server
COPY --from=builder /output/register-server /usr/bin

LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/registration-server-rhel9" \
      cpe="cpe:/a:redhat:confidential_cluster_operator:4.21::el9" \
      version="0.2.1" \
      release="1" \
      description="Registration server for confidential cluster operator" \
      io.k8s.description="HTTP server for registering confidential workloads and managing attestation" \
      url="https://github.com/confidential-clusters/operator" \
      vcs-type="git" \
      vcs-ref="" \
      distribution-scope="public" \
      com.redhat.component="confidential-cluster-operator-registration-server"

EXPOSE 3030
ENTRYPOINT ["/usr/bin/register-server"]


FROM builder AS compute-pcrs-data
# reference-values is vendored as a git submodule (pinned commit), fetched by the Konflux
# git-clone task and copied from the build context. This replaces an in-build `git clone`,
# which cannot run under hermetic (network-isolated) builds.
COPY reference-values reference-values
RUN mkdir -p /output/reference-values && \
    mv /build/reference-values/efivars /output/reference-values/ && \
    mv /build/reference-values/mok-variables /output/reference-values/

FROM ${deployment_base} AS compute-pcrs
COPY --from=compute-pcrs-data /output/compute-pcrs /usr/bin
COPY --from=compute-pcrs-data /output/reference-values /reference-values

LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/compute-pcrs-rhel9" \
      cpe="cpe:/a:redhat:confidential_cluster_operator:4.21::el9" \
      version="0.2.1" \
      release="1" \
      description="PCR computation tool for confidential cluster operator" \
      io.k8s.description="Tool for computing Platform Configuration Register values for confidential VMs" \
      url="https://github.com/confidential-clusters/operator" \
      vcs-type="git" \
      vcs-ref="" \
      distribution-scope="public" \
      com.redhat.component="confidential-cluster-operator-compute-pcrs"

ENTRYPOINT ["/usr/bin/compute-pcrs"]

# Allow environments without --target support, which only read the last stage, to set the stage through the build arg
FROM ${build_target} AS final
