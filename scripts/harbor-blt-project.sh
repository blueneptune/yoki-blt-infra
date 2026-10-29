#!/usr/bin/env bash
# Give blt its place in Harbor: a private project "blt" and two robot
# accounts, then hand each secret to the one thing that uses it - never
# printed, never in a file in this repository.
#
#   scripts/harbor-blt-project.sh
#
# - robot "push" (push + pull): podman on this machine logs in with it
#   (stored in podman's auth file, ${XDG_RUNTIME_DIR}/containers/auth.json).
# - robot "pull" (pull only):   Secret blt/harbor-pull, which the blt
#   namespace's default service account uses for every pod.
#
# Safe to re-run: an existing robot is deleted and made again, which also
# rotates its secret. Needs KUBECONFIG for the core cluster; reads the
# Harbor admin password from the harbor-admin Secret.
set -euo pipefail

REGISTRY="${REGISTRY:-registry.blt.lab.ethos.home}"
PROJECT=blt
here="$(cd "$(dirname "$0")/.." && pwd)"
ca="$here/clusters/core/addons/cert-manager/ethos-home-root-ca.crt"

# Rootless podman trusts the lab CA for this registry only.
install -D -m 0644 "$ca" "$HOME/.config/containers/certs.d/$REGISTRY/ca.crt"

admin="$(kubectl -n harbor get secret harbor-admin -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)"
# The password goes to curl in a file descriptor, not on its command line.
harbor() {
    local method="$1" path="$2"; shift 2
    curl -sS --fail-with-body --cacert "$ca" -X "$method" \
        --netrc-file <(printf 'machine %s login admin password %s\n' "$REGISTRY" "$admin") \
        -H 'Content-Type: application/json' "https://$REGISTRY/api/v2.0$path" "$@"
}

if harbor HEAD "/projects?project_name=$PROJECT" >/dev/null 2>&1; then
    echo "project $PROJECT: exists"
else
    harbor POST /projects -d "{\"project_name\": \"$PROJECT\", \"metadata\": {\"public\": \"false\"}}" >/dev/null
    echo "project $PROJECT: created (private)"
fi

# make_robot NAME ACTION... -> prints the robot's JSON (name + secret)
make_robot() {
    local name="$1"; shift
    local id access project_id
    project_id="$(harbor GET "/projects/$PROJECT" | field project_id)"
    # Project robots are listed only when asked for by project.
    id="$(harbor GET "/robots?q=Level%3Dproject%2CProjectID%3D$project_id&page_size=100" | python3 -c '
import json, sys
for r in json.load(sys.stdin):
    if r["name"].endswith("+" + sys.argv[1]):
        print(r["id"])' "$name")"
    for i in $id; do harbor DELETE "/robots/$i" >/dev/null; done
    access="$(printf '{"resource": "repository", "action": "%s"},' "$@")"
    harbor POST /robots -d "{
        \"name\": \"$name\", \"level\": \"project\", \"duration\": -1,
        \"description\": \"blt $name (scripts/harbor-blt-project.sh)\",
        \"permissions\": [{\"kind\": \"project\", \"namespace\": \"$PROJECT\",
                           \"access\": [${access%,}]}]}"
}

field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

push="$(make_robot push push pull)"
field secret <<<"$push" | podman login --username "$(field name <<<"$push")" --password-stdin "$REGISTRY" >/dev/null
echo "robot push: podman on $(hostname -s) is logged in to $REGISTRY"

pull="$(make_robot pull pull)"
python3 -c '
import base64, json, sys
r = json.load(sys.stdin)
auth = base64.b64encode((r["name"] + ":" + r["secret"]).encode()).decode()
print(json.dumps({"auths": {sys.argv[1]: {"auth": auth}}}))' "$REGISTRY" <<<"$pull" |
    kubectl -n blt create secret docker-registry harbor-pull \
        --from-file=.dockerconfigjson=/dev/stdin --dry-run=client -o yaml |
    kubectl apply -f - >/dev/null
echo "robot pull: Secret blt/harbor-pull updated"
