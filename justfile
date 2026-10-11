set shell := ["bash", "-euo", "pipefail", "-c"]

# nixpkgs branches checked by `just matrix` and the weekly CI job
branches := "nixos-26.05 nixos-25.11 nixos-unstable"

_default:
    just --list

test: testUtilities runTests checkFlake

testUtilities:
    python3 -B util/test_utilities.py

runTests:
    nix shell -c sudo ./run-tests-in-container.sh

checkFlake:
    nix flake check

doc:
    nix run .#updateReadme

testReadme:
    nix run .#testReadme

# Evaluate util/test-containers.nix against a nixpkgs branch, rev, or flake ref
evalWith nixpkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    ref=$(just _ref "{{ nixpkgs }}")
    echo "evalWith $ref"
    nix eval --impure --raw --expr "
      let
        self = builtins.getFlake (toString ./.);
        nixpkgs = builtins.getFlake \"$ref\";
      in
      \"nixpkgs \${nixpkgs.rev or \"dirty\"} (\${nixpkgs.lastModifiedDate}): \" + (self.lib.evalContainers {
        system = builtins.currentSystem;
        inherit nixpkgs;
        config = ./util/test-containers.nix;
      }).config.system.build.etc.drvPath"
    echo

# Run `nix flake check --no-build` against a nixpkgs branch, rev, or flake ref
checkWith nixpkgs:
    nix flake check --no-build --override-input nixpkgs "$(just _ref '{{ nixpkgs }}')"

# Evaluate the examples against a nixpkgs branch, rev, or flake ref and this checkout
examplesWith nixpkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    ref=$(just _ref "{{ nixpkgs }}")
    key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA test"
    for example in flake agent vpn; do
        echo "examplesWith $ref: $example"
        PROJECT_ROOT=/tmp CONTAINER_SSH_KEY="$key" nix eval --impure --raw \
            --override-input extra-container . --override-input nixpkgs "$ref" \
            "./examples/$example#packages.$(nix eval --impure --raw --expr builtins.currentSystem).default.drvPath"
        echo
    done

# Build and run the VM test against a nixpkgs branch, rev, or flake ref (needs KVM, slow)
vmTestWith nixpkgs:
    nix build --no-link --print-out-paths --override-input nixpkgs "$(just _ref '{{ nixpkgs }}')" .#checks.x86_64-linux.test

# Evaluation-only compatibility checks for one nixpkgs version
compatWith nixpkgs: (evalWith nixpkgs) (checkWith nixpkgs) (examplesWith nixpkgs)

# Evaluation-only compatibility checks for every branch in `branches`
matrix:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=()
    for branch in {{ branches }}; do
        just compatWith "$branch" || failed+=("$branch")
    done
    if ((${#failed[@]})); then
        echo "FAILED: ${failed[*]}" >&2
        exit 1
    fi
    echo "All branches passed: {{ branches }}"

# Expand a bare branch name or rev to a nixpkgs flake ref; pass full refs through unchanged
_ref nixpkgs:
    @if [[ "{{ nixpkgs }}" == *:* ]]; then echo "{{ nixpkgs }}"; else echo "github:NixOS/nixpkgs/{{ nixpkgs }}"; fi
