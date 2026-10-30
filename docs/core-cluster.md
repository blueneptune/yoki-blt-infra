# The lab core cluster, as built

What is actually running in the home lab, and how to reach it. The
plan it follows is in the README and [servers.md](servers.md); where it
differs, this page is right.

## Servers

| Name | Address | Role |
|---|---|---|
| `blt-core-01.lab.ethos.home` | 192.168.51.21 | control plane, etcd, workloads |
| `blt-core-02.lab.ethos.home` | 192.168.51.22 | control plane, etcd, workloads |
| `blt-core-03.lab.ethos.home` | 192.168.51.23 | control plane, etcd, workloads |

Rocky Linux 9.8, 4 vCPU and 16 GB each, SELinux enforcing. Disks: 60 GiB
system, 200 GiB `/data/rke2` (sdb), 200 GiB Longhorn (sdc) - both LVM, grown
from 100 GiB on 2026-10-28 (`pvresize` + `lvextend -r`, online). SSH as
`blue` (key only), passwordless sudo.

| Address | What |
|---|---|
| 192.168.51.29 | Kubernetes API (kube-vip, floats between the three) |
| 192.168.51.20 | Traefik - every `*.blt.lab.ethos.home` name points here |

## Installed by hand (2026-10-25)

Not by `scripts/install-rke2-server.sh` - that branch
(`F/Core_rke2_install`) was written for bare servers and is kept only as
`archive/rke2-install-script`.

- **RKE2** v1.36.5+rke2r1, Canal networking, data under `/data/rke2`.
- **kube-vip** v1.3.1, API address and LoadBalancer services, on `ens192`.
- **Traefik** (RKE2's own), the default ingress class.
- **Longhorn** 1.9.2, 200 GiB per server at `/var/lib/longhorn` (30 GiB
  held back), three
  copies by default (storage class `longhorn`, the default).
- **Rancher** 2.15 at `rancher.blt.lab.ethos.home`, and the Longhorn UI
  at `longhorn.blt.lab.ethos.home`. The owner's; blt does not touch them.

## Added from this repository (2026-10-27)

| What | Where |
|---|---|
| CloudNativePG 1.30.1 | `clusters/core/addons/cloudnative-pg/` |
| Storage class `longhorn-single` (one copy, for self-replicating workloads) | `clusters/core/addons/longhorn-single.yaml` |
| cert-manager 1.21.2, ClusterIssuer `step-ca` (ACME, HTTP-01 via Traefik) | `clusters/core/addons/cert-manager/` |
| blt: Postgres `blt-pg`, API, Prefect server and worker, ingress | `clusters/core/blt/` (`kubectl apply -k`) |

Certificates come from the lab CA at `https://ca.lab.ethos.home` (root
"Ethos Home Root CA", in `clusters/core/addons/cert-manager/`).

## Reaching it

The kubeconfig is the cluster's admin credential: keep it at
`~/.kube/blt-core.yaml`, mode 600, never in a repository.

```
ssh blue@192.168.51.21 'sudo cat /etc/rancher/rke2/rke2.yaml' > ~/.kube/blt-core.yaml
chmod 600 ~/.kube/blt-core.yaml
sed -i 's#https://127.0.0.1:6443#https://192.168.51.29:6443#' ~/.kube/blt-core.yaml
export KUBECONFIG=~/.kube/blt-core.yaml
```

Use a `kubectl` of the same minor version as the cluster (1.36).

## DNS

The nodes, and so the pods (CoreDNS forwards to the nodes'
`/etc/resolv.conf`), ask two servers, picking one at random:

- 192.168.50.1, the Firewalla: owns `ethos.home` (cv-toaster, eth00dev1, ...)
  and sends `lab.ethos.home` to 192.168.51.3.
- 192.168.51.3, CoreDNS on the lab side: owns `lab.ethos.home` (ca, the
  nodes, `*.blt.lab.ethos.home`) and sends everything else, `ethos.home`
  included, to the Firewalla.

Both must give the same answer for every name. Until 2026-10-28,
192.168.51.3 also claimed `ethos.home` and answered "no such name" for
cv-toaster, so about half the collections failed to find the CommServe.
The fix was in its Ansible vars (the `ethos.home` entry removed from
`coredns_zones`), not in the cluster.

## Deploying a new blt version

Images go through Harbor (`registry.blt.lab.ethos.home/blt/...`):

```
cd ../blt-v5-poc && TAG=2026.10.30.1 && git checkout $TAG     # the release tag (README, Releases)
podman build -t localhost/blt-api:$TAG -f Containerfile .
podman build -t localhost/blt-prefect-server:$TAG -f deploy/prefect/server/Containerfile .
podman build -t localhost/blt-prefect-worker:$TAG -f deploy/prefect/worker/Containerfile .
cd ../yoki-blt-infra
scripts/push-images.sh $TAG
# set newTag in clusters/core/blt/kustomization.yaml to $TAG, then
kubectl apply -k clusters/core/blt
```

`scripts/harbor-blt-project.sh` made the `blt` project, logged podman in
with its push robot and gave the cluster its pull secret; re-run it on a
new build machine, or to rotate both robots' secrets.
(`scripts/load-images.sh`, copying images onto each server, is the
fallback for when Harbor is down.)

Secrets (`scripts/postgres-secrets.sh`, `scripts/blt-secrets.sh`) are
made once; re-run `blt-secrets.sh` after changing `blt.env`.
