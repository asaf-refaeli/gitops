#!/usr/bin/env bash
# Creates the kind cluster, and nothing else. Installing anything into it is
# bootstrap.sh's job, so a broken bootstrap never means rebuilding the cluster.
# Safe to re-run: an existing cluster is kept.
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER=release-notes
# kind names the single node's container <cluster>-control-plane.
NODE="${CLUSTER}-control-plane"

# Fail early with a clear message instead of a confusing error from kind.
command -v docker >/dev/null || { echo "ERROR: docker is not installed." >&2; exit 1; }
command -v kind >/dev/null || { echo "ERROR: kind is not installed." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker is not running." >&2; exit 1; }

# -x: whole-line match, so a cluster named e.g. "release-notes-old" does not count.
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo ">> kind cluster '$CLUSTER' already exists, keeping it."
  # A cluster created without kind/cluster.yaml has no port mapping, and one
  # cannot be added to a running container. Without it the URLs never work,
  # so stop here instead of failing much later in the browser.
  if ! docker port "$NODE" 2>/dev/null | grep -q '^30080/tcp'; then
    echo "ERROR: '$NODE' does not publish port 30080 (host :80)." >&2
    echo "       Recreate it: ./scripts/down.sh && ./scripts/up.sh" >&2
    exit 1
  fi
  exit 0
fi

echo ">> Creating kind cluster '$CLUSTER'..."
# --wait: return only when the node is Ready, so bootstrap.sh can start at once.
kind create cluster --name "$CLUSTER" --config kind/cluster.yaml --wait 120s
