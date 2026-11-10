#!/usr/bin/env bash
# The Secret a location's blt collector needs, in its own cluster: the
# Prefect API login and blt's API key, read from blt's config/blt.env.
# Nothing is printed or written to disk: each value goes from the file
# straight into the Secret. Run again to update it.
#
#   KUBECONFIG=~/.kube/blt-<location>.yaml scripts/collector-secrets.sh ~/development/blt-v5-poc/config/blt.env
#
#   blt-collector   PREFECT_AUTH (user:password), BLT_API_KEY
#
# Until blt has an API key that may only collect (TODO 25, with Zitadel)
# this is blt's own key: keep the location cluster's admins to the people
# who already hold it.
set -euo pipefail

NAMESPACE=blt-collector
ENV_FILE="${1:?usage: $0 path/to/blt.env}"

from_env() {  # the value of KEY in ENV_FILE, quotes stripped
    local v
    v="$(grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-)"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    [[ -n "$v" ]] || { echo "$1 is not set in $ENV_FILE" >&2; exit 1; }
    printf '%s' "$v"
}

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE" >/dev/null
kubectl -n "$NAMESPACE" create secret generic blt-collector \
    --from-literal=PREFECT_AUTH="$(from_env PREFECT_AUTH)" \
    --from-literal=BLT_API_KEY="$(from_env BLT_API_KEY)" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "blt-collector: applied"
