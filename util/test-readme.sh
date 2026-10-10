#!/usr/bin/env bash
set -euo pipefail

repoDir=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
export PATH="$repoDir:$PATH"

if [[ ${1-} == --extract ]]; then
    exec python3 "$repoDir/util/readme.py" extract-example
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

example=$(mktemp)
trap 'rm -f "$example"' EXIT
python3 "$repoDir/util/readme.py" extract-example > "$example"
bash -n "$example"
trap 'status=$?; extra-container destroy demo || status=1; rm -f "$example"; exit "$status"' EXIT

# Keep the documented commands intact while checking their observable results.
sudo() { "$@"; }
curl() {
    local response
    response=$(command curl --fail --silent --show-error --noproxy '*' \
        --connect-timeout 2 --max-time 5 --retry 30 --retry-delay 1 \
        --retry-connrefused --retry-max-time 60 "$@")
    [[ $response == hello ]] || {
        echo "Expected 'hello', got '$response'" >&2
        return 1
    }
    printf '%s\n' "$response"
}
nixos-container() {
    local status
    status=$(command nixos-container "$@")
    [[ $status == up ]] || {
        echo "Expected container status 'up', got '$status'" >&2
        return 1
    }
    printf '%s\n' "$status"
}

# shellcheck source=/dev/null
source "$example"
containers=$(extra-container list)
if grep -qx demo <<< "$containers"; then
    echo "Example failed to destroy container 'demo'." >&2
    exit 1
fi
trap 'rm -f "$example"' EXIT
echo "README example passed."
