# github-actions-runner

Self-hosted GitHub Actions runner on Docker.

## Files

- `Dockerfile`: builds the runner image
- `start.sh`: registers and starts the runner
- `.env.example`: required environment variables

## Usage

1. Copy `.env.example` to `.env` and fill in `GITHUB_REPO` and `ACCESS_TOKEN`.
2. Build the image:

```bash
docker build -t rockdai/github-actions-runner:latest .
```

3. Run the container:

```bash
docker run --rm -it \
  --env-file .env \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v runner-action-cache:/home/runner/_action-cache \
  rockdai/github-actions-runner:latest
```

The `-v runner-action-cache:…` volume persists the **action archive cache** across container restarts so that actions (e.g. `actions/checkout`, `actions/setup-java`) are downloaded only once instead of on every run. See [GitHub docs](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/managing-access-to-self-hosted-runners#configuring-the-action-archive-cache) for details.

## Pre-installed tools

Node.js and pnpm are baked into the runner tool cache:

- **Node.js** — pinned by `NODE_VERSION` (default `22.13.1`). `actions/setup-node@v4` reports `Found in cache` and skips the download for workflows pinning `node-version: 22` or `22.13`.
- **pnpm** — pinned by `PNPM_VERSION` (default `10.33.4`), installed globally into Node's bin directory. Workflows can drop `pnpm/action-setup` and call `pnpm` directly once `setup-node` puts Node on `PATH`.

Override either at build time:

```bash
docker build \
  --build-arg NODE_VERSION=22.20.0 \
  --build-arg PNPM_VERSION=10.33.4 \
  -t rockdai/github-actions-runner:latest .
```

Workflows pinning a different major/minor (e.g. `node-version: 20`) still work — `setup-node` falls back to downloading on first use. Workflows that keep `pnpm/action-setup` also still work; the action installs its own copy at a higher-priority `PATH` entry.

## Slow / restricted networks

The image is tuned for runners on slow or restricted networks (e.g. mainland China):

- `SEGMENT_DOWNLOAD_TIMEOUT_MINS=3` — `actions/cache` (used by `actions/setup-node` / `setup-python` / etc.) aborts a stuck cache-segment download after 3 minutes instead of the upstream default of 10 minutes, so an unreachable Actions cache CDN can't eat the entire job timeout.
- `npm_config_registry=https://registry.npmmirror.com/` — `npm`, `pnpm`, and `yarn` default to the npmmirror.com mirror instead of `registry.npmjs.org`.

Override either with `-e VAR=value` on `docker run`. To restore upstream defaults:

```bash
docker run ... \
  -e SEGMENT_DOWNLOAD_TIMEOUT_MINS=10 \
  -e npm_config_registry=https://registry.npmjs.org/ \
  rockdai/github-actions-runner:latest
```

For other ecosystems (pip, Maven, Go modules, …), inject the corresponding env var the same way — env vars set on the runner process propagate to job steps.

## Publishing

The bundled GitHub Actions workflow only builds on `release.published`, and it runs on GitHub hosted runners so the image pipeline does not depend on this self-hosted runner image already existing.

If you publish a GitHub Release from a tag like `v1.2.3`, the workflow pushes:

- `rockdai/github-actions-runner:1.2.3`
- `rockdai/github-actions-runner:1.2`
- `rockdai/github-actions-runner:1`
- `rockdai/github-actions-runner:latest`

For pre-release tags, the Docker metadata action will keep the version tags, while `latest` follows Docker's default semver behavior.
