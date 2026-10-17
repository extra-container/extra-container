#!/usr/bin/env bash
set -euo pipefail

repoDir=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
export PATH="$repoDir:$PATH"

if [[ ${1-} == --extract ]]; then
    exec cat "$repoDir/examples/readme/example.sh"
fi
if (($#)); then
    echo "Usage: $0 [--extract]" >&2
    exit 1
fi
if ((EUID != 0)); then
    exec sudo env PATH="$PATH" NIX_PATH="${NIX_PATH-}" bash "$0"
fi

containers=$(extra-container list)
systemContainers=$(command nixos-container list)
if grep -qx demo <<< "$containers" || grep -qx demo <<< "$systemContainers"; then
    echo "Refusing to overwrite existing container 'demo'." >&2
    exit 1
fi

python3 "$repoDir/util/readme.py" check-example
example="$repoDir/examples/readme/example.sh"
bash -n "$example"
cleanup() {
    local status=$?
    extra-container destroy demo || status=1
    exit "$status"
}
trap cleanup EXIT

# shellcheck source=util/readme-shims.sh
source "$repoDir/util/readme-shims.sh"
# shellcheck source=/dev/null
source "$example"
containers=$(extra-container list)
if grep -qx demo <<< "$containers"; then
    echo "Example failed to destroy container 'demo'." >&2
    exit 1
fi
# Issue #4: destroy left the container dir behind
for dir in /var/lib/nixos-containers/demo /var/lib/containers/demo; do
    if [[ -e $dir ]]; then
        echo "Example failed to remove $dir." >&2
        exit 1
    fi
done
trap - EXIT
echo "README example passed."
