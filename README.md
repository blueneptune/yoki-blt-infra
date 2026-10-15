# yoki-blt-infra

Where blt runs: the Kubernetes clusters, the platform pieces on them,
and how each application is deployed onto them.

The applications themselves live in their own repositories and publish
container images (blt's collector and API today; its UI later). This
repository says where and how those images run.

> **Status:** nothing here has run yet. The servers for the first cluster
> are being requested; until they exist, scripts and manifests are
> written from RKE2's and each project's documentation.

## Zones and clusters

```
customer zone(s)     <-->   proxy zone                <-->   core zone
backup servers              cluster "proxy" (3 nodes)        cluster "core" (3 nodes)
(CommServes, VBR...)        Prefect workers: all             Prefect server, blt API, blt UI,
                            collection happens here          Zitadel, Postgres
```

- The proxy zone can reach core and the customer zones; customer zones
  reach only the proxy zone; core reaches neither. Every cross-zone call
  therefore starts in the proxy zone: Prefect workers ask core for work
  and send results to core's API.
- **For now** there is only `core`, and it also runs a Prefect worker.
  `proxy` follows once three more servers exist.

## Layout

```
clusters/
  core/
    rke2/        RKE2 configuration for the core servers
    addons/      platform pieces, as HelmChart manifests RKE2 applies itself:
                 kube-vip, cert-manager, Longhorn, CloudNativePG
  proxy/         (later)
apps/
  base/          blt API, Prefect server and worker, Postgres - per app
  overlays/      per cluster: core-dev first, then production, proxy
scripts/         installing RKE2 on a server, joining one, getting kubectl access
docs/            servers.md (what to ask for), runbooks
```

- **Kustomize** for our own applications, **Helm** for third-party ones -
  through RKE2's built-in Helm controller, so a chart is a small YAML
  file rather than a command someone has to remember to run.
- **Later:** a GitOps tool (Fleet, or Argo CD) applying this repository
  automatically. Not needed to start.

## Decisions so far

| | |
|---|---|
| Kubernetes | RKE2 on Rocky Linux 9, three servers per cluster (embedded etcd, survives losing one) |
| Floating address | kube-vip: one spare IP the `*.blt` hostnames point at |
| Storage | Longhorn, on a second disk in each server |
| Postgres | CloudNativePG |
| Certificates | cert-manager; core's `*.blt.ecp.ensono.com` certificate from the company CA, on core's ingress only |
| Authentication between zones | Zitadel machine users first; mTLS (step-ca + cert-manager) later |
| Images | ghcr.io to start (assumed - not yet confirmed); an internal registry when the proxy zone arrives |

## Branches and releases

The same loop as the other repositories: `F/`, `B/` and `H/` branches,
nothing committed to `main` directly. Not on a weekly clock - a change
here is released when a cluster needs it.
