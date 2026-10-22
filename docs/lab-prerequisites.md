# Lab prerequisites - blt.ethos.home

Everything needed to stand blt up in the home lab the way it will run in
production: an RKE2 core cluster, certificates from the lab's smallstep
CA, and real systems to collect from. Tick items off as they are ready.

**Blocks** says what each item holds up: **core** - the first cluster;
**access** - the first access zone; **source** - collecting from that
system; *later* - nothing yet.

Server sizes and ports are explained in [servers.md](servers.md).

---

## 1. Core cluster servers

| | Item | Blocks |
|---|---|---|
| [ ] | 3 VMs, **Rocky Linux 9** minimal: `blt-core-01`, `blt-core-02`, `blt-core-03` | core |
| [ ] | Each: **4 vCPU, 16 GB RAM**, 60 GB system disk | core |
| [ ] | Each: a **second, empty 100 GB disk** (Longhorn storage) - unformatted, no partitions | core |
| [ ] | Static IP each, all on one subnet | core |
| [ ] | SELinux left **enforcing**; `chronyd` running | core |
| [ ] | `firewalld` **off** on these three - or tell me it must stay on, and I open the ports in servers.md | core |
| [ ] | **RKE2 not yet installed** - see the note below | core |

**About installing RKE2:** `scripts/install-rke2-server.sh` in this
repository installs and configures it (SELinux, the VIP, Longhorn's disk,
the add-ons). Running it on bare Rocky servers proves the same script
that will build production. If you would rather install RKE2 yourself,
that works too - then tell me, and I adapt instead of install.

## 2. Access zone servers (first access zone)

| | Item | Blocks |
|---|---|---|
| [ ] | 3 VMs, Rocky Linux 9: e.g. `blt-az1-01..03` | access |
| [ ] | Each: **2 vCPU, 8 GB RAM**, 60 GB system disk (no second disk - access zones keep no data) | access |
| [ ] | Static IPs on a subnet that **can reach** core and the systems below | access |
| [ ] | *Optional:* a separate VLAN whose firewall lets it reach core and the sources, but stops core reaching it - rehearses the real zone rules | *later* |

Until these exist, collection runs on a Prefect worker in core, as today.

## 3. Addresses

| | Item | Blocks |
|---|---|---|
| [ ] | One **spare IP** on the core subnet, used by nothing - the core cluster's address (kube-vip) | core |
| [ ] | One spare IP on the access subnet, for the access cluster | access |
| [ ] | The VMs' **network interface name** (`ens18` on Proxmox, `ens192` on VMware, ...) | core |

## 4. DNS

In the DNS server that answers for `ethos.home`:

| | Record | Points to | Blocks |
|---|---|---|---|
| [ ] | `blt-core-01/02/03.ethos.home` | each core VM | core |
| [ ] | `*.blt.ethos.home` (wildcard) | the core spare IP | core |
| [ ] | `blt-az1-01/02/03.ethos.home` | each access VM | access |
| [ ] | Which DNS server it is - some home routers cannot do wildcards | | core |

The wildcard covers every hostname: `auth`, `api`, `ui`, `admin`,
`prefect`, `registry`, `grafana`.

## 5. Certificates - the lab's smallstep CA

| | Item | Blocks |
|---|---|---|
| [ ] | step-ca's **URL** as the VMs will reach it (e.g. `https://ca.ethos.home:9000`), and the VMs can reach it | core |
| [ ] | The **root certificate** (`root_ca.crt` - the public half) and its **fingerprint** (`step ca root`, `step certificate fingerprint root_ca.crt`) | core |
| [ ] | A **JWK provisioner** for the cluster: `step ca provisioner add blt-cluster --create`. **Keep its password** - you will put it into the cluster yourself with one command, so it never passes through chat | core |
| [ ] | The CA **allows** `*.blt.ethos.home` (if it restricts names) | core |
| [ ] | The root certificate **installed on your desktop** (Windows certificate store), so browsers trust `*.blt.ethos.home` | core |

Certificates are issued and renewed automatically by cert-manager and
step-issuer; nothing is issued by hand.

## 6. Access for setting it up

| | Item | Blocks |
|---|---|---|
| [ ] | On every VM, a user with `sudo` that accepts this SSH key (from eth00dev1): | core |

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKPjKpioBHJFeAAWoYaqoj4S0rwPcAjdg/DD/3V8Odv blueneptune@gmail.com
```

| | Item | Blocks |
|---|---|---|
| [ ] | eth00dev1 can reach every VM on **22** (SSH) and the cluster VIPs on **6443** (Kubernetes API) | core |
| [ ] | Confirmation that these VMs are **dedicated** and may be rebuilt | core |

## 7. Outbound from the VMs

| | Item | Blocks |
|---|---|---|
| [ ] | Internet access to `docker.io`, `ghcr.io`, `quay.io`, `registry.k8s.io`, `get.rke2.io`, `rpm.rancher.io`, `github.com` - or tell me it is blocked, and a registry mirror comes first | core |

## 8. GitHub

| | Repository | Blocks |
|---|---|---|
| [ ] | `blueneptune/yoki-blt-infra` - this repository, pushed with its branches | core |
| [ ] | `blueneptune/yoki-py-netbackup-sdk` - pushed with its `v0.1.0` tag | source |
| [ ] | *Later:* `yoki-py-vmware-sdk`, `yoki-py-servicenow-sdk`, `yoki-py-rubrik-sdk` - created when each is started | *later* |

## 9. Systems to collect from

A **read-only** account on each. Nothing in blt changes them.

| | System | What I need | Status |
|---|---|---|---|
| [x] | **Commvault** - `cv-toaster` | in place | collecting |
| [ ] | **vCenter** | hostname, version, a user with the **Read-only** role assigned at the vCenter root and propagated; a self-signed certificate is fine (or its CA) | you have one |
| [ ] | **NetBackup** | primary server hostname, version (10.0, 10.5 or 11.0 - the SDK handles all three), port **1556** reachable, an **API key** for a user with a read-only role | in progress |
| [ ] | **Veeam Backup & Replication** | server hostname, version (12 or 13), port **9419** reachable, a user with the **Veeam Backup Viewer** role | in progress |
| [ ] | **Rubrik** | Rubrik is managed through its SaaS console (Rubrik Security Cloud); without a tenant, the SDK is built from documentation and tested against fakes, as Veeam's was | not available |
| [ ] | **ServiceNow** | a free **Personal Developer Instance** from developer.servicenow.com works for building the CMDB reader; a user with read access to the CMDB tables | *later* |

For each, also: can the access zone (or, until it exists, the core
cluster) reach it?

## 10. Optional

| | Item | For |
|---|---|---|
| [ ] | An SMTP server or test mailbox | Zitadel's password resets; notifications |
| [ ] | A Teams or Slack webhook | notifications |

---

## Order of work once ready

1. Sections 1, 3-8 complete: build the core cluster (RKE2, kube-vip,
   cert-manager + step-issuer, Longhorn, CloudNativePG), prove it
   survives losing a server.
2. Certificates from step-ca, then Harbor at `registry.blt.ethos.home`.
3. Postgres databases; blt's API; the Prefect server and a core worker,
   collecting from `cv-toaster`.
4. Zitadel at `auth.blt.ethos.home`.
5. Section 2: the first access zone, with its worker connecting back.
6. Section 9, source by source: probes first, then collection.
