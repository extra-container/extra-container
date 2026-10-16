# 1.0.0-pre.1

- Hardening & security improvements (BREAKING, see below)

- Adopting semver version numbering (major.minor.patch, with an optional pre-release suffix such as `-pre.1`). Breaking changes always bump at least the minor version.
- New release branches starting with 1.0: each minor version has a branch `release-x.y` that only receives non-breaking fixes, so a flake input such as `github:extra-container/extra-container/release-1.0` picks up patch releases on `nix flake update`. `main` is the development branch and may contain breaking changes. Releases are tagged `vX.Y.Z`. See [RELEASING.md](./RELEASING.md).

- **BREAKING**: the host nix daemon socket is no longer accessible inside containers.
  - Before: every container could connect to the host nix daemon (the NixOS container module bind-mounts `/nix/var/nix/daemon-socket`). The daemon identifies clients by host UID, so container root, and any container user whose UID matched a host user in `nix.settings.trusted-users` (e.g. via `@wheel`), was a trusted nix user, which is equivalent to root on the host. Untrusted container users could also reach daemon vulnerabilities such as CVE-2026-110450.
  - After: the socket is masked. Inside the container, nix commands that build or substitute (`nix build`, `nix run`, `nix develop`, `nix-shell`) fail with `cannot connect to socket at '/nix/var/nix/daemon-socket/socket'`.
  - To restore the old behavior for a container: `extra.hostNixDaemon = true;`. Read the option description (and the Security section of the README) first.
- Enhancements
  - New option `extra.overlayStore.enable` (default: false): run a nix daemon inside the container with a private store layered over the host store (OverlayFS). `nix build`, `nix develop` etc. work inside the container without access to the host nix daemon and without modifying the host store. Uses the experimental `local-overlay` store type. Builds run without the nix sandbox, which doesn't work in nspawn containers.
  - New option `extra.overlayStore.gcRoots.enable` (default: true): periodically add host GC roots for host store paths used by the container's store, so that host garbage collection doesn't break the container store.
- Fixes
  - `extra-container destroy` failed to remove the container directory (`rm: cannot remove '.../var/empty': Operation not permitted`) on systems without `chattr` in `PATH`, e.g. NixOS systems with systemd in stage 1 and no ext filesystems ([#4](https://github.com/extra-container/extra-container/issues/4)). extra-container now provides `chattr` (e2fsprogs).
- Tests
  - The VM test checks that the daemon socket is masked by default and reachable with `extra.hostNixDaemon = true`.
  - The VM test checks builds with `extra.overlayStore`: the host store is not modified, GC roots protect host paths used by the container, and `destroy` removes the upper layer and GC roots.
  - The VM test runs the README example on a system without e2fsprogs and checks that `destroy` removes the container directory. `util/test-readme.sh` checks this too.

# 0.17

- Project moved to [github.com/extra-container/extra-container](https://github.com/extra-container/extra-container)
- Enhancements
  - Support NixOS 26.05 and nixos-unstable
  - New examples:
    - [examples/agent](./examples/agent): development sandbox for agent development
    - [examples/vpn](./examples/vpn): container whose traffic goes through a WireGuard VPN;
      uses a reusable `services.wgnet` host module.
  - Add CI (flake check, nixfmt, shellcheck, utility tests, example evaluation)
- Fixes
  - `assertions` and `warnings` are now checked when building containers.
    Previously they were silently ignored, because NixOS only checks them when
    building `system.build.toplevel`, which extra-container does not use.
  - The VM test (`nix flake check`) now fails when the container test fails
- Development
  - Removed use of ruby, replaced with bash & python
  - Replaced Makefile with justfile
  - Dropped `i686-linux` from `supportedSystems`
  - Add `just evalWith|checkWith|examplesWith|compatWith|matrix|vmTestWith` and a weekly CI
    job for checking compatibility with other nixpkgs versions

# 0.16 (2026-09-09)

- Fixes
  - Added two dummy options for compatibility with latest nixpkgs-unstable:
    `nix.enable`
    `nix.daemon.enable`
  - Fixed test bugs. All tests pass.
  - Shellcheck cleanup on all bash scripts
  - Format README.md

# 0.15 (2026-04-28)

- Fixes
  - Declare additional dummy options in `eval-config.nix` so containers
    evaluate cleanly against current `nixpkgs-unstable`. Newer
    `nixos/modules/system/boot/systemd.nix` references
    `services.openssh.{enable,package}` (for the `sshd-vsock@`
    systemd-vmspawn unit), `security.polkit.enable`,
    `security.pam.services`, `services.logrotate.settings`,
    `system.nixos-init.package`, `time.timeZone`, and
    `users.groups.utmp.name` at the outer eval level. Replaces the
    leaf-typed `security` and `services.logrotate` dummies with their
    specific child paths so submodule writes are accepted. Fixes #40.

# 0.14 (2025-12-19)

- Enhancements
  - Support NixOS unstable

# 0.13 (2024-12-12)

- Enhancements
  - Support NixOS option `containers.<name>.autoStart`.
    This allows creating containers that are automatically started on system boot.
  - Support NixOS 24.11, NixOS unstable

# 0.12 (2023-06-15)

- Enhancements
  - Flake: Allow accessing built container configs.
    Example:
    ```bash
    nix eval ./examples/flake --apply 'sys: sys.containers.demo.config.networking.hostName'
    ```
  - Add compatibility with NixOS 23.05, NixOS unstable
- Fixes
  - Fix `extra-container destroy --all` when more than one container is installed

# 0.11 (2022-10-22)

- Enhancements
  - Support building containers via Flakes (see [examples/flake](./examples/flake)).
  - Support destroying containers from container definitions:\
    If you have installed containers with command `extra-container create ./mycontainers.nix`,
    you can now destroy these containers with the analogous command
    `extra-container destroy ./mycontainers.nix`.
- Fixes
  - Fix incomplete container state directory path in `help()` message

# 0.10 (2022-06-26)

- Enhancements
  - Support NixOS 22.05

# 0.9 (2022-04-11)

- Enhancements
  - Support NixOS unstable
- Fixes
  - Fix command `destroy` for nested declarative containers

# 0.8 (2021-09-30)

- Enhancements
  - Support NixOS unstable
- Fixes
  - Fix flake

# 0.7 (2021-08-03)

- Enhancements
  - Support NixOS 21.05 and unstable
  - Add basic [Nix flake](https://nixos.wiki/wiki/Flakes) support
    for installing and developing.\
    `extra-container` itself still uses `nix-build` internally.

# 0.6 (2021-02-05)

- Fixes
  - Add compatibility with current NixOS unstable.
  - `extra.exposeLocalhost`: don't fail when iptables lock can't be obtained immediately.
  - Fix `PATH` not being preserved in container shells.

# 0.5 (2020-11-01)

- Enhancements. (See the [README](README.md) for full documentation.)
  - Add generic support for systemd-based Linux distros.
  - Add command `shell`.
  - Add extra container options:\
    `extra.enableWAN`\
    `extra.exposeLocalhost`\
    `extra.firewallAllowHost`\
    See [eval-config.nix](eval-config.nix) for descriptions.
  - Add option `--ssh`.
  - Add option `--expr|-E`.
  - Append `pwd` to `NIX_PATH` to allow accessing the working dir in non-file configs.
  - Support nixpkgs versions > 20.03.
  - Automatically run as root via `sudo`.
- Fixes
  - Don't copy local nixpkgs sources provided via `--nixpkgs` to the nix store.

# 0.4 (2020-09-25)

- Enhancements
  - Significantly speed up container evaluation.\
    Use a reduced module set for evaluating the container host system derivation.
  - Speed up container destruction.\
    Kill the container process instead of a clean shutdown.
