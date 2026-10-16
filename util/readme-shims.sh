# shellcheck shell=bash
# Shims for running the README example as a test.
# Keep the documented commands intact while checking their observable results.
# Sourced by util/test-readme.sh and the VM test in flake.nix.

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
