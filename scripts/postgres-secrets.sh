#!/usr/bin/env bash
# Create the Postgres passwords the operator does not create itself.
# Each is random, generated here and sent straight to the cluster - it is
# never printed or written to disk. Re-running leaves existing ones alone.
#
#   KUBECONFIG=~/.kube/blt-core.yaml scripts/postgres-secrets.sh
set -euo pipefail

NAMESPACE=blt

make_login() {  # secret name, role name
    if kubectl -n "$NAMESPACE" get secret "$1" >/dev/null 2>&1; then
        echo "$1: already there, left alone"
        return
    fi
    kubectl -n "$NAMESPACE" create secret generic "$1" \
        --type=kubernetes.io/basic-auth \
        --from-literal=username="$2" \
        --from-literal=password="$(openssl rand -base64 33 | tr -d '/+=\n')" \
        --dry-run=client -o yaml \
        | kubectl label --local -f - cnpg.io/reload=true -o yaml \
        | kubectl apply -f - >/dev/null
    echo "$1: created"
}

make_login blt-pg-prefect prefect
