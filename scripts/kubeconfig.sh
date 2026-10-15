#!/usr/bin/env bash
# Fetch kubectl access to a cluster from its first server, pointed at the
# cluster's floating address (the VIP) rather than one server.
#
#   ./scripts/kubeconfig.sh core <ssh-user>
#
# Writes ~/.kube/blt-<cluster>.kubeconfig (owner-only). Use it with
#   export KUBECONFIG=~/.kube/blt-core.kubeconfig
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${1:?usage: $0 <cluster> <ssh-user>}"
USER_AT="${2:?usage: $0 <cluster> <ssh-user>}"
# shellcheck disable=SC1090
source "$REPO/clusters/$CLUSTER/cluster.env"
OUT="$HOME/.kube/blt-$CLUSTER.kubeconfig"
mkdir -p "$HOME/.kube"
umask 077
ssh "$USER_AT@$FIRST_SERVER" sudo cat /etc/rancher/rke2/rke2.yaml \
    | sed -e "s#https://127.0.0.1:6443#https://$VIP:6443#" -e "s/: default$/: blt-$CLUSTER/" > "$OUT"
echo "Wrote $OUT. Try: KUBECONFIG=$OUT kubectl get nodes"
