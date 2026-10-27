#!/usr/bin/env bash
# Create the secrets blt's own services need, from blt's config/blt.env
# and the Postgres secrets the operator and postgres-secrets.sh made.
# Nothing is printed or written to disk: each value goes from the file or
# the cluster straight into a secret. Run again to update them.
#
#   KUBECONFIG=~/.kube/blt-core.yaml scripts/blt-secrets.sh ~/development/blt-v5-poc/config/blt.env
#
#   blt-app      BLT_API_KEY, BLT_DATABASE_URL (to blt-pg-rw), PREFECT_AUTH
#                (the Prefect UI/API login, user:password)
set -euo pipefail

NAMESPACE=blt
ENV_FILE="${1:?usage: $0 path/to/blt.env}"

from_env() {  # the value of KEY in ENV_FILE, quotes stripped
    local v
    v="$(grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-)"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    [[ -n "$v" ]] || { echo "$1 is not set in $ENV_FILE" >&2; exit 1; }
    printf '%s' "$v"
}

from_secret() {  # secret, key
    kubectl -n "$NAMESPACE" get secret "$1" -o "jsonpath={.data.$2}" | base64 -d
}

urlquote() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""), end="")'; }

db_password="$(from_secret blt-pg-app password | urlquote)"

kubectl -n "$NAMESPACE" create secret generic blt-app \
    --from-literal=BLT_API_KEY="$(from_env BLT_API_KEY)" \
    --from-literal=PREFECT_AUTH="$(from_env PREFECT_AUTH)" \
    --from-literal=BLT_DATABASE_URL="postgresql+psycopg://blt:${db_password}@blt-pg-rw.${NAMESPACE}.svc:5432/blt" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "blt-app: applied"
