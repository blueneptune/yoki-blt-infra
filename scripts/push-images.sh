#!/usr/bin/env bash
# Push blt images built on this machine to Harbor, under the blt project:
#   localhost/blt-api:TAG  ->  registry.blt.lab.ethos.home/blt/api:TAG
#
#   scripts/push-images.sh TAG
#
# Needs the podman login made by scripts/harbor-blt-project.sh. Replaces
# scripts/load-images.sh (copying images onto each node) now there is a
# registry.
set -euo pipefail

REGISTRY="${REGISTRY:-registry.blt.lab.ethos.home}"
[[ $# -eq 1 ]] || { echo "usage: $0 TAG" >&2; exit 64; }
tag="$1"

for name in api prefect-server prefect-worker; do
    target="$REGISTRY/blt/$name:$tag"
    podman tag "localhost/blt-$name:$tag" "$target"
    podman push -q "$target"
    echo "pushed $target"
done
