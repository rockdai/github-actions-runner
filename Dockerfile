FROM ubuntu:24.04

ARG RUNNER_VERSION=2.333.1

ENV DEBIAN_FRONTEND=noninteractive

# Basic dependencies. python3 + build-essential are needed by node-gyp so jobs that
# install npm packages with native deps (node-pty, better-sqlite3, etc.) can compile
# from source when no prebuild matches the runner kernel.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    python3 \
    sudo \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (for service containers like PostgreSQL)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Runner user with sudo (needed for actions/setup-* and Docker socket fix)
RUN groupadd -f docker && \
    useradd -m -s /bin/bash -G sudo,docker runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner && \
    chmod 0440 /etc/sudoers.d/runner

# GitHub Actions runner
WORKDIR /home/runner
RUN ARCH=$(dpkg --print-architecture) && \
    case "${ARCH}" in \
      amd64) ARCH='x64' ;; \
      arm64) ARCH='arm64' ;; \
      *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz" && \
    tar xzf runner.tar.gz && \
    rm runner.tar.gz && \
    ./bin/installdependencies.sh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Tool cache for actions/setup-node, actions/setup-java, etc.
RUN mkdir -p /opt/hostedtoolcache && chown runner:runner /opt/hostedtoolcache
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache

# Pre-install Node.js + pnpm into the tool cache so actions/setup-node finds
# Node without hitting the network, and pnpm is available on PATH alongside
# it. setup-node matches by semver, so workflows pinning `22` or `22.13`
# (the major/minor of NODE_VERSION) reuse this build's binary. Override
# versions or the registry with --build-arg NODE_VERSION=... / PNPM_VERSION=...
# / NPM_REGISTRY=...
ARG NODE_VERSION=22.13.1
ARG PNPM_VERSION=10.33.4
ARG NPM_REGISTRY=https://registry.npmmirror.com/
RUN ARCH=$(dpkg --print-architecture) && \
    case "${ARCH}" in \
      amd64) ARCH='x64' ;; \
      arm64) ARCH='arm64' ;; \
      *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    NODE_DIR="/opt/hostedtoolcache/node/${NODE_VERSION}/${ARCH}" && \
    NODE_TGZ="node-v${NODE_VERSION}-linux-${ARCH}.tar.gz" && \
    mkdir -p "${NODE_DIR}" && \
    curl -fsSL --retry 3 --retry-delay 5 -o /tmp/node.tar.gz \
      "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TGZ}" && \
    EXPECTED_SHA=$(curl -fsSL --retry 3 --retry-delay 5 \
                     "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
                   | awk -v f="${NODE_TGZ}" '$2==f{print $1}') && \
    [ -n "${EXPECTED_SHA}" ] && \
    echo "${EXPECTED_SHA}  /tmp/node.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/node.tar.gz -C "${NODE_DIR}" --strip-components=1 && \
    rm /tmp/node.tar.gz && \
    touch "/opt/hostedtoolcache/node/${NODE_VERSION}/${ARCH}.complete" && \
    "${NODE_DIR}/bin/node" --version && \
    "${NODE_DIR}/bin/npm" install -g "pnpm@${PNPM_VERSION}" \
      --registry="${NPM_REGISTRY}" \
      --no-audit --no-fund && \
    "${NODE_DIR}/bin/pnpm" --version && \
    chown -R runner:runner /opt/hostedtoolcache/node

# Action archive cache to avoid re-downloading actions on every run
RUN mkdir -p /home/runner/_action-cache && chown runner:runner /home/runner/_action-cache
ENV ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=/home/runner/_action-cache

# Cap @actions/cache segment downloads at 3 minutes (default 10). When the
# Actions cache CDN is unreachable from the runner network, restore stalls
# for the full 10-minute window per segment and burns the job timeout.
ENV SEGMENT_DOWNLOAD_TIMEOUT_MINS=3

# Default npm/pnpm/yarn to the same registry the build used (NPM_REGISTRY arg,
# default npmmirror). The upstream registry.npmjs.org is slow enough from this
# runner's network to time out 15-min jobs on its own. Override at runtime
# with -e npm_config_registry=...
ENV npm_config_registry=${NPM_REGISTRY}

RUN chown -R runner:runner /home/runner

COPY start.sh ./start.sh
RUN chmod +x start.sh

ENTRYPOINT ["./start.sh"]
