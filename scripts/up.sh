#!/usr/bin/env bash
# The one command: from a machine with Docker and kind to both environments
# running. Two scripts so each part can be re-run on its own.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/create-cluster.sh
./scripts/bootstrap.sh
