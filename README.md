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

## Publishing

The bundled GitHub Actions workflow only builds on `release.published`, and it runs on GitHub hosted runners so the image pipeline does not depend on this self-hosted runner image already existing.

If you publish a GitHub Release from a tag like `v1.2.3`, the workflow pushes:

- `rockdai/github-actions-runner:1.2.3`
- `rockdai/github-actions-runner:1.2`
- `rockdai/github-actions-runner:1`
- `rockdai/github-actions-runner:latest`

For pre-release tags, the Docker metadata action will keep the version tags, while `latest` follows Docker's default semver behavior.
