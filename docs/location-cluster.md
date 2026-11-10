# A location cluster: blt's collector inside a location's network

blt runs in **core**. Some backup products are in networks core cannot
reach - another region, a customer's network. Each such **location** gets
a small Kubernetes cluster of its own, inside that network, running a
**blt collector**: a Prefect worker that takes the runs for the sources
only it can reach and sends what it collects to core.

```
core cluster (blt namespace)                       location cluster (blt-collector namespace)
  prefect.blt.<domain>  <-- https 443 -------------- blt-collector pods (2)
  api.blt.<domain>      <-- https 443 --------------   ask Prefect for work (queue "<location>")
  registry.blt.<domain> <-- https 443 --------------   pull the worker image
                                                       |
                                                       +--> NetBackup / Commvault / Rubrik in this location
```

The location connects **out** to core; core never connects in. That is
the rule the network zones set (core | access | customer): a location
cluster sits in an access zone, which may reach core and its customers.

## How work gets there

Exactly as for a remote collector on a tools server (blt-v5-poc
docs/remote-collector.md), without the ssh tunnel:

- Each source names its collector (Administration -> Sources ->
  Collector). Its runs - schedules, checks, Run now - go to that
  collector's work queue in core's Prefect pool `blt`.
- The collector's pods take only that queue. Two replicas share it, each
  run going to one of them. Since blt 2026.11.10 that is safe: the lock
  that keeps one source's runs apart, and the one around a Commvault
  token renewal, are held in core's Prefect (`blt-lock-*` concurrency
  limits), not in a pod.
- A run's hold on a lock is a lease the pod renews while it runs; a pod
  that dies lets go within two minutes.

## Two steps

1. **Now: the worker as a Deployment** (this directory). The pods run
   each flow run as a process, as blt's own worker does in core.
   `clusters/location/blt-collector` is the base; a location is an
   overlay that names it (`clusters/lab-location/blt-collector` is the
   example).
2. **Next: a pod per flow run.** A Prefect **Kubernetes work pool** for
   the location: its worker starts each flow run as its own Kubernetes
   Job, from blt's worker image, with the run's own CPU and memory limits
   - one run's trouble never touches another's, and the cluster spreads
   them over its nodes. Needs: the `prefect-kubernetes` package in blt's
   worker image, a work pool per location (`blt-<location>`, type
   `kubernetes`) whose base job template names the image, namespace,
   service account and the core-ca ConfigMap, a Role letting the worker
   create Jobs in its namespace, and blt routing a source's runs to its
   location's pool rather than to a queue of `blt`. The locks above are
   what makes it possible: with a pod per run, nothing else is shared.

## Setting one up

What the location's servers need is in [servers.md](servers.md) (three
servers, or one for a small location: see "Sizing" below), with the
firewall rules below in place of core's ingress rules.

```bash
# 1. The cluster: RKE2 as for core (core-cluster.md), without Longhorn,
#    Harbor, CloudNativePG or cert-manager - a collector keeps no data.
# 2. Trust core's registry on each node: clusters/core/nodes/registries.yaml
#    and hosts.toml, as on core's nodes (scripts/node-trust.sh).
# 3. The pull Secret, as for core (docs/harbor.md), in namespace blt-collector.
# 4. The collector's Secret, from blt's config/blt.env:
KUBECONFIG=~/.kube/blt-<location>.yaml scripts/collector-secrets.sh ~/development/blt-v5-poc/config/blt.env
# 5. An overlay for the location (copy clusters/lab-location), then:
KUBECONFIG=~/.kube/blt-<location>.yaml kubectl apply -k clusters/<location>/blt-collector
# 6. In blt: Administration -> Sources -> Collectors shows it online; set
#    each of the location's sources' Collector to it, and check each.
```

## Firewall

From the location cluster's nodes (pods leave through them):

| To | Port | For |
|---|---|---|
| `prefect.blt.<domain>` (core's ingress address) | 443/tcp | asking for work, run state, logs, blocks, locks |
| `api.blt.<domain>` (the same address) | 443/tcp | sending what it collected |
| `registry.blt.<domain>` (the same address) | 443/tcp | pulling blt's worker image |
| each NetBackup primary | 1556/tcp, or 443/tcp (some 10.5 primaries) | NetBackup's API |
| each CommServe | 443/tcp (Command Center's API), or the port its URL names | Commvault's API |
| `*.my.rubrik.com` | 443/tcp | Rubrik Security Cloud |
| `api.metallic.io` | 443/tcp | Commvault Cloud |
| DNS, NTP | 53/udp+tcp, 123/udp | the location's own resolvers and time servers |

Nothing needs to reach the location cluster from outside it except
`kubectl` (6443/tcp) from wherever it is administered.

## DNS and certificates

- The location's resolvers must answer `*.blt.<domain>` with core's
  ingress address.
- Core's certificates are signed by core's CA (step-ca in the lab). The
  collector trusts it through the `core-ca` ConfigMap (`SSL_CERT_FILE`,
  `PREFECT_API_SSL_CERT_FILE`), and the nodes trust it for pulling
  images (registries.yaml). With a publicly signed certificate on core
  instead, neither is needed.
- The collector holds no certificate of its own. Later (vision.md, 6),
  core's step-ca may issue each location a client certificate for mTLS
  to core, through cert-manager in the location cluster.

## Sizing

A collector holds no data, so a location cluster is small:

| | Small location (a few sources) | Larger, or highly available |
|---|---|---|
| Servers | 1 | 3 (control plane + etcd on each) |
| CPU / memory each | 4 vCPU, 8 GB | 4 vCPU, 8-16 GB |
| Disk | 60 GB system, 50 GB for `/var/lib/rancher` | the same |
| Spare IP | none (no ingress) | one, for the Kubernetes API (kube-vip) |

One server is a single point of failure, but only for collection: blt
in core keeps everything collected so far, and the next run after the
server is back collects everything since the last one that worked.

## Not yet

- An API key that may only collect (with Zitadel); today the collector
  holds blt's own key. Keep the location cluster's admins to people who
  already hold it.
- Step 2 above (a pod per flow run).
- A `blt` image build in the location's own registry, if pulling from
  core's Harbor across the network is too slow or not allowed.
