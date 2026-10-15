#!/usr/bin/env bash
# Install RKE2 on one server of a cluster, as root, on Rocky Linux 9.
#
#   First server:      sudo ./install-rke2-server.sh core --first [--longhorn-disk /dev/sdb]
#   The other two:     sudo RKE2_TOKEN=... ./install-rke2-server.sh core --join [--longhorn-disk /dev/sdb]
#
# <cluster> names clusters/<cluster>/cluster.env (copy it from the
# .example next to it). The token for --join is printed at the end of
# --first; it is never written into this repository.
#
# Safe to re-run: it rewrites the config and restarts nothing that is
# already running unless the config changed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${1:?usage: $0 <cluster> --first|--join [--longhorn-disk DEVICE] [--disable-firewalld]}"
shift
ROLE="" DISK="" DISABLE_FIREWALLD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --first) ROLE=first ;;
        --join) ROLE=join ;;
        --longhorn-disk) DISK="${2:?--longhorn-disk needs a device}"; shift ;;
        --disable-firewalld) DISABLE_FIREWALLD=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ -n "$ROLE" ]] || { echo "say --first or --join" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

ENV_FILE="$REPO/clusters/$CLUSTER/cluster.env"
[[ -f "$ENV_FILE" ]] || { echo "$ENV_FILE not found - copy cluster.env.example" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${VIP:?} ${VIP_INTERFACE:?} ${FIRST_SERVER:?}"

say() { echo "==> $*"; }

# --- the machine -----------------------------------------------------------
. /etc/os-release
[[ "${ID:-}" == "rocky" && "${VERSION_ID%%.*}" == "9" ]] \
    || echo "warning: written for Rocky Linux 9, this is ${PRETTY_NAME:-unknown}" >&2

if ! ip link show "$VIP_INTERFACE" >/dev/null 2>&1; then
    echo "VIP_INTERFACE=$VIP_INTERFACE does not exist on this server ($(hostname))." >&2
    exit 1
fi

if swapon --show | grep -q .; then
    say "Turning swap off (Kubernetes expects none)"
    swapoff -a
    sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
fi

if systemctl is-active -q firewalld; then
    if [[ "$DISABLE_FIREWALLD" == true ]]; then
        say "Stopping firewalld, as asked"
        systemctl disable --now firewalld
    else
        echo "firewalld is running. Either open the ports in docs/servers.md, or re-run with" >&2
        echo "--disable-firewalld (what RKE2's documentation recommends)." >&2
        exit 1
    fi
fi

# NetworkManager must leave the pod network's interfaces alone, or it
# interferes with Canal (a known RKE2 issue on RHEL-family systems).
cat > /etc/NetworkManager/conf.d/rke2-canal.conf <<'NM'
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:flannel*
NM
systemctl reload NetworkManager

say "Packages Longhorn needs (iSCSI, NFS)"
dnf install -y -q iscsi-initiator-utils nfs-utils cryptsetup device-mapper
systemctl enable --now iscsid

# --- Longhorn's disk -------------------------------------------------------
if [[ -n "$DISK" ]]; then
    if mountpoint -q /var/lib/longhorn; then
        say "/var/lib/longhorn is already mounted - leaving it"
    else
        # Only an empty disk: no partitions, no filesystem, not mounted.
        if [[ -n "$(lsblk -nro NAME "$DISK" | tail -n +2)" ]] || blkid -p "$DISK" >/dev/null 2>&1; then
            echo "$DISK is not empty (it has partitions or a filesystem). Refusing to format it." >&2
            exit 1
        fi
        say "Formatting $DISK (xfs) for Longhorn at /var/lib/longhorn"
        mkfs.xfs -q "$DISK"
        mkdir -p /var/lib/longhorn
        echo "UUID=$(blkid -s UUID -o value "$DISK") /var/lib/longhorn xfs defaults 0 0" >> /etc/fstab
        mount /var/lib/longhorn
    fi
fi

# --- RKE2 configuration ----------------------------------------------------
mkdir -p /etc/rancher/rke2
{
    sed '/@TLS_SANS@/d' "$REPO/clusters/$CLUSTER/rke2/config.yaml.tmpl" | sed -n '1,/^tls-san:/p'
    for san in "$VIP" ${TLS_SANS:-}; do echo "  - $san"; done
    sed -n '/@TLS_SANS@/,$p' "$REPO/clusters/$CLUSTER/rke2/config.yaml.tmpl" | tail -n +2
    if [[ "$ROLE" == join ]]; then
        : "${RKE2_TOKEN:?set RKE2_TOKEN - it is printed at the end of --first}"
        echo "server: https://${FIRST_SERVER}:9345"
        echo "token: ${RKE2_TOKEN}"
    fi
} > /etc/rancher/rke2/config.yaml.new
chmod 600 /etc/rancher/rke2/config.yaml.new
CHANGED=true
if [[ -f /etc/rancher/rke2/config.yaml ]] && cmp -s /etc/rancher/rke2/config.yaml.new /etc/rancher/rke2/config.yaml; then
    CHANGED=false
fi
mv /etc/rancher/rke2/config.yaml.new /etc/rancher/rke2/config.yaml

# --- install ---------------------------------------------------------------
if ! command -v rke2 >/dev/null 2>&1 && [[ ! -x /usr/bin/rke2 ]]; then
    say "Installing RKE2 (${RKE2_VERSION:-channel ${RKE2_CHANNEL:-stable}})"
    if [[ -n "${RKE2_VERSION:-}" ]]; then
        curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="$RKE2_VERSION" sh -
    else
        curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${RKE2_CHANNEL:-stable}" sh -
    fi
fi

# The first server deploys the cluster's add-ons: RKE2 applies anything
# in this directory itself, and keeps it applied.
if [[ "$ROLE" == first ]]; then
    MANIFESTS=/var/lib/rancher/rke2/server/manifests
    mkdir -p "$MANIFESTS"
    sed -e "s/@VIP@/$VIP/g" -e "s/@VIP_INTERFACE@/$VIP_INTERFACE/g" \
        "$REPO/clusters/$CLUSTER/addons/kube-vip.yaml.tmpl" > "$MANIFESTS/blt-kube-vip.yaml"
    for addon in cert-manager longhorn cloudnative-pg; do
        cp "$REPO/clusters/$CLUSTER/addons/$addon.yaml" "$MANIFESTS/blt-$addon.yaml"
    done
fi

say "Starting rke2-server (the first start takes several minutes)"
systemctl enable rke2-server
if [[ "$CHANGED" == true ]] && systemctl is-active -q rke2-server; then
    systemctl restart rke2-server
else
    systemctl start rke2-server
fi

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH="$PATH:/var/lib/rancher/rke2/bin"
for _ in $(seq 1 60); do
    kubectl get node "$(hostname)" >/dev/null 2>&1 && break
    sleep 5
done
kubectl get nodes -o wide || true

if [[ "$ROLE" == first ]]; then
    echo
    say "First server up. To join the other two, on each of them:"
    echo "    sudo RKE2_TOKEN='<token>' ./scripts/install-rke2-server.sh $CLUSTER --join ..."
    echo "  The token is in /var/lib/rancher/rke2/server/node-token on this server:"
    echo "    sudo cat /var/lib/rancher/rke2/server/node-token"
fi
