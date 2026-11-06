# Flux (trial, 2026-11-06)

Flux keeps the cluster matching this repo: it reads git every minute and
applies what changed, so a merge is a deploy and a revert is a rollback.
Chosen over Argo CD (another UI, where blt's UI is to be the one UI) and
Rancher's Fleet (tied to Rancher); Flux can also watch Harbor and bump
`newTag` itself - the manual step of a blt release.

The repo is public, so Flux reads it over https with no credentials.
Nothing secret is in git: `scripts/*-secrets.sh` still make the secrets,
and Flux deletes only objects it made itself.

## The trial

| Path | What |
|---|---|
| `clusters/core/flux-system/` | Flux v2.10.0: source, kustomize and notification controllers (`gotk-components.yaml`, generated) |
| `clusters/core/flux-trial/` | where Flux looks: this repo, branch `F/Flux_trial`, path `clusters/core/flux-trial/app` |
| `clusters/core/flux-trial/app/` | a test page, https://flux-trial.blt.lab.ethos.home - nothing of blt's |

Install (once, by hand - after that, git):

```
export KUBECONFIG=~/.kube/blt-core.yaml
kubectl apply -k clusters/core/flux-system     # Flux itself
flux check                                     # all controllers ready
kubectl apply -k clusters/core/flux-trial      # what it should follow
flux get kustomizations --watch                # flux-trial: Applied revision ...
```

Watch it work: change `version 1` (and the `flux-trial/version`
annotation) or `replicas` in `app/hello.yaml`, push to `F/Flux_trial`,
and within a minute or two the page and the pods follow. `flux reconcile
kustomization flux-trial --with-source` skips the wait.

Useful:

```
flux get sources git                 # which commit Flux has
flux get kustomizations              # applied, or why not
flux events                          # what it did, newest last
flux suspend kustomization flux-trial    # stop syncing (hands-on fix); resume to restart
```

## Removing it

```
kubectl delete -k clusters/core/flux-trial     # Flux prunes the test app
kubectl delete namespace flux-trial            # in case it was suspended
flux uninstall --keep-namespace=false          # Flux and its CRDs
```

## If it stays: next steps

1. Flux follows `main`, and a Kustomization for `clusters/core/blt`
   (`prune: true`) takes over from `kubectl apply -k`. A hand
   `kubectl edit` on blt is then put back within a minute.
2. Image automation (image-reflector and image-automation controllers):
   watches `registry.blt.lab.ethos.home/blt/*` for new release tags and
   commits the `newTag` bump - needs a deploy key with write access and
   Harbor's pull robot.
3. blt's UI shows Flux's state (Kustomization status) under
   Administration.
