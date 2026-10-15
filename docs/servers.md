# Servers for a cluster

What to ask for, per cluster. Three servers make one highly available
cluster: each runs the control plane and its database (etcd), and the
cluster keeps working with one of them down.

## Each server

| | |
|---|---|
| OS | Rocky Linux 9, minimal install |
| CPU / memory | 4 vCPU, 16 GB RAM (RKE2 itself needs 2 and 4 GB; the rest is for the applications) |
| Disk | 60 GB for the system, plus a second **empty** disk of 100 GB for Longhorn |
| Network | static IP, same subnet as the other two, a DNS name (`blt-core-01..03`) |
| SELinux | enforcing - RKE2 supports it |
| Time | NTP (chronyd) running - etcd is sensitive to clocks that disagree |

## Per cluster

- **One spare IP** on the same subnet, assigned to nothing. kube-vip
  moves it between the servers; it is the cluster's address for
  `kubectl` and, through the ingress, for the `*.blt` hostnames.

## Network

Between the three servers, either `firewalld` off on these servers (what
RKE2's documentation recommends) or these open:

| Port | Protocol | For |
|---|---|---|
| 6443 | TCP | Kubernetes API (also from wherever `kubectl` is run) |
| 9345 | TCP | RKE2 supervisor: servers joining |
| 2379-2381 | TCP | etcd |
| 10250 | TCP | kubelet |
| 8472 | UDP | pod network (Canal VXLAN) |
| 9099 | TCP | pod network health checks |
| 30000-32767 | TCP | NodePort services |
| 80, 443 | TCP | ingress - also from users |
| 9500-9504 | TCP | Longhorn, between servers |

Outbound: the container registries (docker.io, ghcr.io, quay.io,
registry.k8s.io), `get.rke2.io` and `rpm.rancher.io` for the install,
github.com. If those are blocked, a registry mirror is needed instead -
say so before installing.

## Access for setting it up

- A user with `sudo` on each server, logging in by SSH key.
- These servers dedicated to this cluster - they will be rebuilt more
  than once while the setup is worked out.
