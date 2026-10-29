#!/usr/bin/env bash
# Make every core server's containerd trust the lab root CA for Harbor
# (registry.blt.lab.ethos.home), so pods can pull from it. Idempotent; no
# restart - containerd reads certs.d on every pull.
#
#   scripts/node-trust.sh
#
# Puts on each server:
#   /etc/rancher/rke2/ethos-home-root-ca.crt
#   /etc/rancher/rke2/registries.yaml          (clusters/core/nodes/)
#   /data/rke2/agent/etc/containerd/certs.d/registry.blt.lab.ethos.home/hosts.toml
#
# Nodes and the SSH user/key come from the environment, as for load-images.sh:
#   NODES="192.168.51.21 192.168.51.22 192.168.51.23" NODE_USER=blue NODE_KEY=~/.ssh/blue_id_ed25519
set -euo pipefail

NODES="${NODES:-192.168.51.21 192.168.51.22 192.168.51.23}"
NODE_USER="${NODE_USER:-blue}"
NODE_KEY="${NODE_KEY:-$HOME/.ssh/blue_id_ed25519}"
REGISTRY=registry.blt.lab.ethos.home

here="$(cd "$(dirname "$0")/.." && pwd)"
ca="$here/clusters/core/addons/cert-manager/ethos-home-root-ca.crt"
registries="$here/clusters/core/nodes/registries.yaml"
hosts="$here/clusters/core/nodes/hosts.toml"

# Refuse an existing registries.yaml we did not write - RKE2 has only one.
for node in $NODES; do
    ssh -i "$NODE_KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$NODE_USER@$node" bash -s \
        "$(base64 -w0 "$ca")" "$(base64 -w0 "$registries")" "$(base64 -w0 "$hosts")" "$REGISTRY" <<'REMOTE'
set -euo pipefail
ca="$1" registries="$2" hosts="$3" registry="$4"
dir=/etc/rancher/rke2
certs=/data/rke2/agent/etc/containerd/certs.d/$registry
if sudo test -f $dir/registries.yaml && ! sudo grep -q "$registry" $dir/registries.yaml; then
    echo "$(hostname -s): $dir/registries.yaml exists and is not ours - not touched" >&2; exit 1
fi
echo "$ca"         | base64 -d | sudo install -m 0644 -o root -g root /dev/stdin $dir/ethos-home-root-ca.crt
echo "$registries" | base64 -d | sudo install -m 0600 -o root -g root /dev/stdin $dir/registries.yaml
sudo install -d -m 0755 "$certs"
echo "$hosts"      | base64 -d | sudo install -m 0644 -o root -g root /dev/stdin "$certs/hosts.toml"
sudo restorecon -R $dir "$(dirname "$certs")" 2>/dev/null || true
echo "$(hostname -s): trusts the lab CA for $registry"
REMOTE
done
