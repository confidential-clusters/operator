# based on ./operator/Containerfile
# SPDX-FileCopyrightText: Alice Frosi <afrosi@redhat.com>
# SPDX-FileCopyrightText: Jakob Naucke <jnaucke@redhat.com>
# SPDX-FileCopyrightText: Yair Podemsky <ypodemsk@redhat.com>
#
# SPDX-License-Identifier: CC0-1.0

ARG build_type=release
ARG build_target=operator

# Unified builder stage, compiles all binaries in a single cargo invocation.
FROM quay.io/redhat-user-workloads/cocl-operator-tenant/buildroot@sha256:34806c0eb874b00bcd0fc90241746404e051070b278ac0351e5c8873ffda8b39 AS builder
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

# controller-gen and kopium are prefetched via cachi2 'generic' (artifacts.lock.yaml) and
# mounted at /cachi2/output/deps/generic. Place them at $(LOCALBIN)=/build/bin with the
# exact `<tool>-<version>` names `make crds-rs` expects, so its existence guards skip the
# network curl / go-install / cargo-install (which don't work under hermetic).
RUN mkdir -p bin && \
    cp /cachi2/output/deps/generic/controller-gen-linux-amd64 bin/controller-gen-v0.20.1 && \
    tar -xJf /cachi2/output/deps/generic/kopium-x86_64-unknown-linux-musl.tar.xz -C bin --strip-components=1 && \
    mv bin/kopium bin/kopium-0.23.0 && \
    chmod +x bin/controller-gen-v0.20.1 bin/kopium-0.23.0

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
FROM registry.access.redhat.com/ubi9/ubi-minimal AS operator
COPY --from=builder /output/operator /usr/bin

# Red Hat labels
LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/confidential-cluster-operator" \
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

FROM registry.access.redhat.com/ubi9/ubi-minimal AS attestation-key-register
COPY --from=builder /output/attestation-key-register /usr/bin

LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/attestation-key-register" \
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

FROM registry.access.redhat.com/ubi9/ubi-minimal AS register-server
COPY --from=builder /output/register-server /usr/bin

LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/registration-server" \
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

FROM registry.access.redhat.com/ubi9/ubi-minimal AS compute-pcrs
COPY --from=compute-pcrs-data /output/compute-pcrs /usr/bin
COPY --from=compute-pcrs-data /output/reference-values /reference-values

LABEL vendor="Red Hat, Inc." \
      name="confidential-clusters-beta/compute-pcrs" \
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
