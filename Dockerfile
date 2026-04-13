FROM ubuntu:24.04

ARG RUNNER_VERSION=2.333.1

ENV DEBIAN_FRONTEND=noninteractive

# Basic dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
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

# Action archive cache to avoid re-downloading actions on every run
RUN mkdir -p /home/runner/_action-cache && chown runner:runner /home/runner/_action-cache
ENV ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=/home/runner/_action-cache

RUN chown -R runner:runner /home/runner

COPY start.sh ./start.sh
RUN chmod +x start.sh

ENTRYPOINT ["./start.sh"]
