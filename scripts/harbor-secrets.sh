#!/usr/bin/env bash
# Harbor's admin password and its encryption key, random, made straight
# into secrets - never printed or written to disk. Re-running leaves
# existing ones alone (changing the encryption key would make what Harbor
# stored with the old one unreadable).
#
#   KUBECONFIG=~/.kube/blt-core.yaml scripts/harbor-secrets.sh
#
# To sign in to Harbor's web page as admin:
#   kubectl -n harbor get secret harbor-admin -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d
set -euo pipefail

NAMESPACE=harbor

random() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

make() {  # secret name, key, length
    if kubectl -n "$NAMESPACE" get secret "$1" >/dev/null 2>&1; then
        echo "$1: already there, left alone"
        return
    fi
    kubectl -n "$NAMESPACE" create secret generic "$1" --from-literal="$2=$(random "$3")" >/dev/null
    echo "$1: created"
}

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE" >/dev/null
make harbor-admin HARBOR_ADMIN_PASSWORD 24
# Harbor requires exactly 16 characters.
make harbor-secret-key secretKey 16
