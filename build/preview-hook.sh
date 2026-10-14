#!/bin/bash
# Runs .preview/deploy.sh against the local docker-compose.dev.yml stack with
# the helpers pr-preview's instance/deploy.sh gives it on a PR preview, so
# `make deploy` and a preview set the server up the same way.
# Usage: build/preview-hook.sh <plugin-id> <plugin-version>
set -euo pipefail

[ -f .preview/deploy.sh ] || exit 0

id="$1"
version="$2"

compose() { ${DOCKER_COMPOSE:-docker compose -f docker-compose.dev.yml} "$@"; }
mmctl_on() { local svc="$1"; shift; compose exec -T "$svc" mmctl --local "$@"; }
mmctl() { mmctl_on mattermost "$@"; }

wait_for_ping() {
  local svc="${1:-mattermost}" _
  for _ in $(seq 1 120); do
    if compose exec -T "$svc" mmctl system status --local >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "mattermost did not become ready"
  return 1
}

echo "Running .preview/deploy.sh for ${id} ${version}..."
# shellcheck disable=SC1091
. .preview/deploy.sh
