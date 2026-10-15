# Harbor - the clusters' own registry

**Status: planned, nothing installed.**

Harbor runs in the core cluster and is the one place both clusters get
container images from:

- **Our images** (blt, later the blt UI and API) are pushed to it by
  whatever builds them.
- **Public images** (RKE2's own, cert-manager, Longhorn, Postgres,
  Prefect, ...) are fetched through it: Harbor's *proxy cache* projects
  pull an image from docker.io, ghcr.io or quay.io the first time it is
  asked for and serve the copy afterwards. The proxy cluster then needs
  no internet access of its own for images.

## Who can reach it

Only the core and proxy clusters. Its ingress allows only their networks
(`HARBOR_ALLOWED_CIDRS`, e.g. the two clusters' subnets) and refuses
everything else - no users, no customer zones. It fits the zone rules:
the proxy zone may call core; core never calls out.

Pushing images from a build machine outside those networks needs that
machine's address added, or the build to run inside the core cluster.

## Order of installation

Harbor needs things that come before it:

1. The core cluster, with cert-manager and Longhorn (the install script).
2. A DNS name for it (e.g. `registry.blt.ecp.ensono.com`) pointing at
   the cluster's VIP.
3. Its TLS certificate as the Secret `harbor-tls` in namespace `harbor`
   (the `*.blt.ecp.ensono.com` certificate covers it).
4. Its admin password as the Secret `harbor-admin`.
5. Then `clusters/core/addons/harbor.yaml.tmpl`, filled in.

Until Harbor is up, the core cluster pulls public images directly from
the internet - it has to, to install Harbor in the first place.

## Pointing the clusters at it

Each server gets `/etc/rancher/rke2/registries.yaml`, which tells RKE2
to fetch docker.io, ghcr.io and quay.io images through Harbor's proxy
cache projects, with a robot account's credentials. That will be part of
the install script once Harbor exists; it is not yet.

## Not decided yet

- How much storage the registry needs (200 GB to start).
- Whether Harbor's own vulnerability scanning (Trivy) is wanted - it is
  on by default and needs internet access for its database, or a mirror.
- Backups of Harbor's database and storage.
