#!/usr/bin/env bash
# Everything after the cluster exists. Only two imperative actions, both
# needed before Argo CD can take over:
#   1. Install Argo CD (it cannot install itself). The argocd Application
#      adopts this release afterwards, so Git owns it from then on.
#   2. The root Application, the one GitOps seed.
# Argo CD creates the app namespaces, and the release-notes chart creates its
# own DB password Secret in the cluster (a PreSync Job), so neither is here.
# After this, every change is a commit. Safe to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."

# Every call names the context explicitly, so the script can never touch
# another cluster in the kubeconfig, whatever the current context is.
CTX=kind-release-notes

for tool in helm kubectl; do
  command -v "$tool" >/dev/null || { echo "ERROR: $tool is not installed." >&2; exit 1; }
done

# --- 1. Argo CD ---------------------------------------------------------------
echo ">> Installing Argo CD..."
# `helm dependency build` refuses a Chart.lock whose repository is not
# registered locally ("no repository definition"), so register it first.
# --force-update makes a re-run a no-op instead of an error.
helm repo add argo https://argoproj.github.io/argo-helm --force-update
# Downloads the pinned upstream chart into charts/ (gitignored), exactly the
# version and digest in Chart.lock.
helm dependency build workloads/platform/argocd
# Release name and namespace must match bootstrap/apps/argocd.yaml, or Argo CD
# would install a second copy instead of adopting this one.
# upgrade --install: installs on the first run, a no-op upgrade on re-runs.
# --wait: return only when every workload in the release is Ready (server,
# repo-server, application-controller and redis), without naming them here.
# On timeout helm fails, and set -e stops the script.
helm --kube-context "$CTX" upgrade --install argo-cd workloads/platform/argocd \
  --namespace argocd --create-namespace \
  --wait --timeout 5m

# --- 2. The GitOps seed --------------------------------------------------------
echo ">> Applying the root Application..."
kubectl --context "$CTX" apply -f bootstrap/root.yaml

# --- 3. Wait until everything is Synced and Healthy -----------------------------
# Expected apps: root plus one per file in bootstrap/apps/ (each file name is
# its Application name). A new file there is picked up with no script change.
apps=(root)
for f in bootstrap/apps/*.yaml; do
  apps+=("$(basename "$f" .yaml)")
done

echo ">> Waiting for ${#apps[@]} Applications to be Synced/Healthy (up to 15 min)..."
# SECONDS is a bash built-in: seconds since the script started.
deadline=$((SECONDS + 900))
while true; do
  pending=()
  for app in "${apps[@]}"; do
    # Children appear only as root syncs them, wave by wave. "|| true" keeps
    # set -e from stopping the script on "not found"; that app is just pending.
    status=$(kubectl --context "$CTX" -n argocd get application "$app" \
      -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    [[ "$status" == "Synced/Healthy" ]] || pending+=("$app")
  done

  if [[ ${#pending[@]} -eq 0 ]]; then
    break
  fi
  if (( SECONDS >= deadline )); then
    echo "ERROR: timed out. Still pending: ${pending[*]}" >&2
    kubectl --context "$CTX" -n argocd get applications >&2 || true
    exit 1
  fi
  echo "   pending: ${pending[*]}"
  sleep 10
done

# --- 4. Where to look ------------------------------------------------------------
cat <<EOF

>> Done. Every Application is Synced and Healthy.

   dev:   http://dev.localhost
   prod:  http://prod.localhost

Argo CD UI (an admin tool, so not exposed through the Gateway):

   kubectl --context $CTX -n argocd port-forward svc/argo-cd-argocd-server 8080:443
   # browse https://localhost:8080 (self-signed certificate), user: admin
   kubectl --context $CTX -n argocd get secret argocd-initial-admin-secret \\
     -o jsonpath='{.data.password}' | base64 -d; echo

EOF
