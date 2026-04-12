#!/bin/bash
set -euo pipefail

# --- Phase 1: Fix Docker socket permissions as root, then re-exec as runner ---
if [ "$(id -u)" = "0" ]; then
  if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    CURRENT_GID=$(getent group docker | cut -d: -f3 || echo "")
    if [ -z "${CURRENT_GID}" ]; then
      groupadd -g "${DOCKER_SOCK_GID}" docker
    elif [ "${DOCKER_SOCK_GID}" != "${CURRENT_GID}" ]; then
      groupmod -g "${DOCKER_SOCK_GID}" docker
    fi
    usermod -aG docker runner
  fi
  # Re-exec as runner user (-H sets HOME=/home/runner, -E preserves env vars)
  exec sudo -E -H -u runner "$0"
fi

# --- Phase 2: Everything below runs as the runner user ---
cd /home/runner

if [ -z "${GITHUB_REPO:-}" ]; then
  echo "Error: GITHUB_REPO is required (e.g. owner/repo)"
  exit 1
fi
if [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "Error: ACCESS_TOKEN is required (GitHub fine-grained PAT with Administration: Read & Write)"
  exit 1
fi

RANDOM_SUFFIX=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 4)
RUNNER_NAME="${RUNNER_NAME:-runner-${RANDOM_SUFFIX}}"
RUNNER_LABELS="${RUNNER_LABELS:-ubuntu}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/home/runner/work}"

# Get registration token
echo "Requesting registration token for ${GITHUB_REPO}..."
REG_TOKEN=$(curl -fsSL \
  -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" | jq -r .token)

if [ "${REG_TOKEN}" = "null" ] || [ -z "${REG_TOKEN}" ]; then
  echo "Error: Failed to get registration token. Check ACCESS_TOKEN permissions."
  exit 1
fi

# Configure runner
ARGS=(
  --url "https://github.com/${GITHUB_REPO}"
  --token "${REG_TOKEN}"
  --name "${RUNNER_NAME}"
  --labels "${RUNNER_LABELS}"
  --work "${RUNNER_WORKDIR}"
  --unattended
  --replace
  --disableupdate
)

./config.sh "${ARGS[@]}"

exec ./run.sh
