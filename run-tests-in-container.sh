#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

scriptDir="$(dirname "$(readlink -f "$0")")"
PATH=$scriptDir:$PATH

# The test container needs nix to build the nested test containers. By default it
# uses the host nix daemon (fast, shares the host's store and substituter config).
# With --overlay, it runs its own daemon on an overlay store instead, which
# exercises nested containers over an overlay store on a real host kernel.
nixAccess='extra.hostNixDaemon = true;'
for arg in "$@"; do
    case $arg in
        --overlay) nixAccess='extra.overlayStore.enable = true;' ;;
        *) echo "Usage: $0 [--overlay]" >&2; exit 1 ;;
    esac
done

# Namespace entry and cleanup need root, not just extra-container commands.
if ((EUID != 0)); then
    exec sudo env PATH="$PATH" NIX_PATH="${NIX_PATH-}" bash "$scriptDir/run-tests-in-container.sh" "$@"
fi

cleanup() {
    # clean immutable files inside the container
    for f in /var/lib/*containers/test-extra-container/var/lib/*containers/*/var/empty; do
        chattr -i -a "$f"
        rm -rf "$f"
    done
    extra-container destroy test-extra-container || true
}
trap "cleanup" EXIT

trap 'echo "Error at $(realpath "${BASH_SOURCE[0]}"):$LINENO"' ERR

cleanup

#―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――

nixpkgs=$(nix-instantiate --eval -E '(toString <nixpkgs>)' | tr -d '"')

extra-container create -s <<EOF
{ config, pkgs, lib, ... }:
{
  containers.test-extra-container = {
    # Destroying nested NixOS containers requires clearing var/empty's immutable flag.
    additionalCapabilities = [ "CAP_LINUX_IMMUTABLE" ];
    bindMounts."/extra-container".hostPath = "$scriptDir";
    bindMounts."/nixpkgs".hostPath = "$nixpkgs";
    $nixAccess
    config = { options, ... }: {
      environment = {
        systemPackages = [ pkgs.nixos-container pkgs.e2fsprogs ];
        variables.NIX_PATH = lib.mkForce "nixpkgs=/nixpkgs";
      };
      boot = lib.optionalAttrs (options.boot ? extraSystemdUnitPaths) {
        extraSystemdUnitPaths = [ "/etc/systemd-mutable/system" ];
      };
    };
  };
}
EOF

echo "Running tests ($nixAccess)"
echo
nixos-container run test-extra-container -- '/extra-container/test.sh'
