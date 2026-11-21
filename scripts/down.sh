#!/usr/bin/env bash
# Deletes the kind cluster and everything in it, including both Postgres
# volumes. Nothing in Git changes: ./scripts/up.sh rebuilds the same state.
set -euo pipefail

cd "$(dirname "$0")/.."

kind delete cluster --name release-notes
