#!/usr/bin/env bash
# Copy images built on this machine into every core node's containerd,
# for as long as there is no registry (Harbor) to pull them from.
#
#   scripts/load-images.sh localhost/blt-api:422c54a localhost/blt-prefect-server:422c54a ...
#
# Nodes and the SSH user/key come from the environment:
#   NODES="192.168.51.21 192.168.51.22 192.168.51.23" NODE_USER=blue NODE_KEY=~/.ssh/blue_id_ed25519
# Manifests then use the same image names with imagePullPolicy: Never.
set -euo pipefail

NODES="${NODES:-192.168.51.21 192.168.51.22 192.168.51.23}"
NODE_USER="${NODE_USER:-blue}"
NODE_KEY="${NODE_KEY:-$HOME/.ssh/blue_id_ed25519}"
CTR="sudo /data/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"

[[ $# -gt 0 ]] || { echo "usage: $0 IMAGE..." >&2; exit 64; }

archive="$(mktemp --suffix=.tar)"
trap 'rm -f "$archive"' EXIT
podman save -q --format docker-archive -m -o "$archive" "$@"

for node in $NODES; do
    (
        ssh -i "$NODE_KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$NODE_USER@$node" \
            "$CTR images import -" <"$archive" >/dev/null
        echo "$node: loaded"
    ) &
done
wait
