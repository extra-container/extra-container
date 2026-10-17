# extra-container

NixOS containers that can be fully managed without system rebuilds.

Standard NixOS declarative containers require a full system module evaluation, which can be prohibitively slow for systems with many containers or for iterative development or experimentation on a running system.

extra-container retains the benefits of NixOS containers: declarative syntax, package/file/uid/network isolation, resource management, a read-only nix store shared with the host, and fast startup times comparable to docker or qemu vms; but unlike standard NixOS containers, they can be created, stopped, and rebuilt, without a nixos-rebuild.

- [Simple flake example](./examples/flake) a simple flake example.
- [Agent development sandbox](./examples/agent): control access granted to agents or other partially-trusted code.
- [WireGuard VPN container](./examples/vpn): split-tunnel networking: everything in the container routes over the vpn, while the host retains its original routes.

> This repo is the successor to [erikarvstedt's](https://github.com/erikarvstedt/extra-container) original and [stevelr's](https://github.com/stevelr/extra-container) fork. `erikarvstedt` created extra-container in 2018, and maintained it through 0.14 in Dec 2025. `stevelr` created a fork in May 2026 and moved it here in Oct 2026. The 0.16 tagged release has the same bits as the 0.16 tag in [stevelr's repo](https://github.com/stevelr/extra-container).

## Example

```bash
sudo extra-container create --start <<'EOF'
{
  containers.demo = {
    privateNetwork = true;
    hostAddress = "10.250.0.1";
    localAddress = "10.250.0.2";

    config = { pkgs, ... }: {
      systemd.services.hello = {
        wantedBy = [ "multi-user.target" ];
        script = ''
          while true; do
            echo hello | ${pkgs.netcat}/bin/nc -lN 50
          done
        '';
      };
      networking.firewall.allowedTCPPorts = [ 50 ];
    };
  };
}
EOF

curl --http0.9 10.250.0.2:50 # Returns 'hello' from the container

# Now change the 'hello' string in the container definition to something
# else and re-run the `extra-container create --start` command.
# The container is automatically updated via NixOS' `switch-to-configuration`.

# The container is a regular container that can be controlled
# with nixos-container
nixos-container status demo

# Remove the container
sudo extra-container destroy demo
```

#### Run command in a container and exit

```bash
cfg='{
  containers.demo.config = {
    networking.hostName = "hello";
  };
}'
extra-container shell -E "$cfg" --run c hostname # => hello
```

## Changelog

[`CHANGELOG.md`](CHANGELOG.md)

## Install

### On NixOS

#### With flakes (recommended)

Add this repository as a flake input and import `extra-container.nixosModules.default`.
This will install the `extra-container` binary.

Alternatively, add `extra-container.overlays.default` to `nixpkgs.overlays` and set
`programs.extra-container.enable = true`.

#### With the nixpkgs module only

Add `programs.extra-container.enable = true` to your configuration (NixOS ≥ 21.11).

Note: the `extra-container` package in nixos-26.05 and nixos-unstable (as of 2026-10-15) still link to v0.14
from the previous upstream repository. That version lacks the compatibility fixes from 0.15 and later
and fails to evaluate containers against recent nixpkgs. Use the flake module or overlay
above until nixpkgs is updated.

### On other systemd-based Linux distros

```bash
git clone https://github.com/extra-container/extra-container
# Calls sudo during install
extra-container/util/install.sh
```

[`install.sh`](util/install.sh) installs `extra-container` to the root nix user profile
and edits `/etc/sudoers` to enable running `extra-container` with sudo.

## More features

### Shell

Command `shell` starts a container shell session.
The shell provides helper functions for interacting with the container. The container is destroyed when exiting the shell.

This config uses `extra` options [explained below](#private-network-helper).

```bash
read -d '' src <<'EOF' || :
{
  containers.demo = {
    extra.addressPrefix = "10.250.0"; # Sets up a private network.
    extra.enableWAN = true;
  };
}
EOF
# Provide container config via `-E` instead of stdin because the shell's stdin
# should be connected to the terminal.
extra-container shell -E "$src" --ssh
```

`extra-container` automatically runs itself via `sudo` when called as a non-root user.

An example shell session

```
...
Starting shell.
Enter "h" for documentation.

$ h
Container address: 10.250.0.2 ($ip)
Container filesystem: /var/lib/nixos-containers/demo

Run "c COMMAND" to execute a command in the container
Run "c" to start a shell session inside the container
Run "cssh" for SSH

# Container internet access, enabled via option `extra.enableWAN`
$ c curl example.com
<!doctype html>
<html>
...

# Connect with SSH, enabled by `--ssh`
$ cssh hostname
demo
```

#### Run commands

Run a command in a shell session and exit. The container is destroyed afterwards.

```bash
cfg='{ containers.demo = {}; }'
extra-container shell -E "$cfg" --run c hostname
# => demo
```

Start a shell inside the container.

```bash
cfg='{ containers.demo = {}; }'
extra-container shell -E "$cfg" --run c
```

#### Repeated calls to `extra-container shell`

When `extra-container shell` detects that it is already running in a container shell
session, it updates the running container instead of destroying and restarting it and
starting a new shell.\
To prevent `sudo` from clearing the environment variables that are needed for shell
detection, call `extra-container` without `sudo`.\
`extra-container` will automatically run itself via `sudo` only when it is first
called as a non-root user outside of a shell session.

To force container destruction inside a shell session, use `extra-container shell --destroy|-d`.

#### Disable auto-destruction

By default, `shell` destroys the shell container before starting and before exiting.
This ensures that containers start with no leftover filesystem state from
previous runs and that containers do not consume system resources after use.\
To disable auto-destructing containers, run
`extra-container shell --no-destroy|-n`

### Private network helper

Container options `extra.*` are defined by `extra-container` and help with setting up private network containers.\
See [eval-config.nix](./eval-config.nix) for full option descriptions.

```nix
containers.demo = {
  extra = {
    # Sets
    # privateNetwork = true
    # hostAddress = "${addressPrefix}.1"
    # localAddress = "${addressPrefix}.2"
    addressPrefix = "10.250.0";

    # Enable internet access for the container
    enableWAN = true;
    # Always allow connections from hostAddress
    firewallAllowHost = true;
    # Make the container's localhost reachable via localAddress
    exposeLocalhost = true;
  }
};
```

### Access working dir in non-file configs

`extra-container` appends `pwd` to `NIX_PATH` to allow configs given via `--expr|-E`
or via stdin to access the working directory.

```bash
extra-container create -E '{ imports = [ <pwd/myfile.nix> ]; ... }'
```

## Security

extra-container containers are NixOS containers (systemd-nspawn). Review these points
before running partially-trusted code in a container.

- **Host nix daemon**: masked by default. With `extra.hostNixDaemon = true`, processes in
  the container can use the host nix daemon (`nix build`, `nix develop`, ...). The daemon
  identifies clients by host UID, so a container user whose UID belongs to a host user in
  `nix.settings.trusted-users` (e.g. `@wheel`) is a trusted nix user, which is equivalent
  to root on the host.
- **Nix inside containers**: `extra.overlayStore.enable = true` runs a nix daemon in the
  container with a private store layered over the host store, so builds work without the
  host daemon and without modifying the host store. Builds run without the nix sandbox,
  which doesn't work in nspawn containers. See the option descriptions in
  [eval-config.nix](./eval-config.nix).
- **UIDs are shared with the host** unless the container sets `privateUsers`. Container
  UID 1000 is host UID 1000 for file access through bind mounts and for the nix daemon.
- **Root in a container is not isolated from the host** unless the container sets
  `privateUsers`. Don't give container root to untrusted code.
- **Network**: without `privateNetwork` (or `extra.addressPrefix`), the container shares
  the host's network, including services listening on the host's localhost.

To report a vulnerability, see [SECURITY.md](./SECURITY.md).

## Usage

```
extra-container create <container-config-file>
                       [--attr|-A attrPath]
                       [--nixpkgs-path|--nixos-path path]
                       [--start|-s | --restart-changed|-r]
                       [--ssh]
                       [--build-args arg...]

    <container-config-file> is a NixOS config file with container
    definitions like 'containers.mycontainer = { ... }'

    --attr | -A attrPath
      Select an attribute from the config expression

    --nixpkgs-path
      A nix expression that returns a path to the nixpkgs source
      to use for building the containers

    --nixos-path
      Like '--nixpkgs-path', but for directly specifying the NixOS source

    --start | -s
      Start all created containers
      Update running containers that have changed or restart them if '--restart-changed' was specified

    --update-changed | -u
      Update running containers with a changed system configuration by running
      'switch-to-configuration' inside the container.
      Restart containers with a changed container configuration

    --restart-changed | -r
      Restart running containers that have changed

    --ssh
      Generate SSH keys in /tmp and enable container SSH access.
      The key files remain after exit and are reused on subsequent runs
      until /tmp is cleared (e.g. on reboot).
      Unlocks the function 'cssh' in 'extra-container shell'.
      Requires container option 'privateNetwork = true'.

    --build-args arg...
      All following args are passed to nix-build.

    Example:
      extra-container create mycontainers.nix --restart-changed

      extra-container create mycontainers.nix --nixpkgs-path \
        'fetchTarball https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz'

      extra-container create mycontainers.nix --start --build-args --builders 'ssh://worker - - 8'

echo <container-config> | extra-container create
    Read the container config from stdin

    Example:
      extra-container create --start <<EOF
        { containers.hello = { enableTun = true; config = {}; }; }
      EOF

extra-container create --expr|-E <container-config>
    Provide container config as an argument

extra-container create <store-path>
    Create containers from <store-path>/etc

    Examples:
      Create from nixos system derivation
      extra-container create /nix/store/..-nixos-system-foo-26.05

      Create from nixos etc derivation
      extra-container create /nix/store/32..9j-etc

extra-container shell ...
    Start a container shell session.
    See the README for a complete documentation.
    Supports all arguments from 'create'

    Extra arguments:
      --run <cmd> <arg>...
        Run command in shell session and exit
        Must be the last option given
      --no-destroy|-n
        Do not destroy shell container before and after running
      --destroy|-d
        If running inside an existing shell session, force container to
        be destroyed before and after running

    Example:
      extra-container shell -E '{ containers.demo.config = {}; }'

extra-container build ...
    Build the container config and print the resulting NixOS system etc path

    This command can be used like 'create', but options related
    to starting are not supported

extra-container list
    List all extra containers

extra-container restart <container>...
    Fixes the broken restart command of nixos-container (nixpkgs issue #43652)

extra-container destroy <container-name>...
    Destroy containers

extra-container destroy <args for create/shell>...
    Destroy the containers defined by the args for command `create` or `shell` (see above).
    For this to work, the first arg after `destroy` must start with one of the
    following three characters: ./-

    Example:
      extra-container destroy ./containers.nix

extra-container destroy --all|-a
    Destroy all extra containers

extra-container <cmd> <arg>...
    All other commands are forwarded to nixos-container
```

## Implementation

The script works like this: Take a NixOS config with container definitions and build
the system's `config.system.build.etc` derivation. Because we're not building a full
system we can use a reduced module set (`eval-config.nix`) to improve evaluation
performance.

Now link the container files from the etc derivation to the main system, like so:

```
nixos-system/etc/systemd/system/container@CONTAINER.service -> /etc/systemd-mutable/system
nixos-system/etc/containers/CONTAINER.conf -> /etc/nixos-containers (system.stateVersion ≥ 22.05)
                                           -> /etc/containers       (system.stateVersion < 22.05)
```

Finally, add gcroots pointing to the linked files.

## Developing

All contributions and suggestions are welcome, even if they're minor or cosmetic.

### Development workflow

Run `nix develop` in the project root directory to start a development shell.\
Within the shell, you can run extra-container from the [local source](./extra-container) via command `extra-container`.

When changing the `Usage` documentation in `extra-container`, run `just doc` to copy
these changes to `README.md`.

The introductory example lives in [examples/readme/example.sh](./examples/readme/example.sh).
Its heredoc must match [container.nix](./examples/readme/container.nix), which the VM
imports to pre-build the container. `just testUtilities` checks both this match and
the README code block. After editing the example, run
`python3 util/readme.py update-example` to copy it into the README.

Run `just testReadme` (or `nix run .#testReadme`) to run the checked-in example.
This needs sudo and a systemd host with Nix;
it checks the HTTP response and container status, and cleans up after failures.
It refuses to run if a container named `demo` already exists.
Run `nix run .#testReadme -- --extract` to print the example without running it.

#### Tests

Run `just test` to run the tests.\
The following tests are executed:

- Utility tests

  Run `just testUtilities` to check the sudoers and README helpers without root.
  Requires Python 3 and Bash.

- Main test suite

  Can be run manually via `sudo run-tests-in-container.sh`.\
  This script creates a temporary container named `test-extra-container` in which
  the main test script [`test.sh`](./test.sh) is run.\
  `test.sh` adds and removes temporary containers named `test-*` on the host system.
  It can also be called directly, but wrapping it with `run-tests-in-container.sh`
  helps reducing interference with your main system.

- VM test

  Can be run manually via `nix build .#test`.\
  This is a basic test using the [NixOS VM test framework](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing-python.nix).
  It is built as a Nix derivation, which makes it independent from the system
  environment.

  For debugging the VM, run `nix run .#debugTest` to start a Python test driver shell
  inside the VM.

- `nix flake check`

  Evaluates all flake outputs and builds the VM test.

#### Testing against other nixpkgs versions

`eval-config.nix` evaluates containers with a reduced NixOS module set and stub options for
everything that set reads. Changes in nixpkgs regularly add new references, which breaks
evaluation with "option does not exist". These recipes check compatibility without root or
a build, taking a branch name, a commit hash, or a full flake ref:

```bash
just evalWith nixos-unstable      # evaluate util/test-containers.nix
just checkWith nixos-26.05        # nix flake check --no-build with --override-input
just examplesWith nixos-unstable  # evaluate the examples against this checkout
just compatWith nixos-unstable    # all three
just matrix                       # compatWith for every branch in `branches`
just vmTestWith nixos-unstable    # build and run the VM test (needs KVM, slow)
```

`just evalWith <commit>` with `git bisect` over nixpkgs finds the exact change that broke
evaluation. [`compat.yml`](.github/workflows/compat.yml) runs `compatWith` for each branch
weekly and on pushes that touch evaluation, and the VM test on the weekly run.

#### VM

Run `nix run .#vm` to start a VM where `extra-container` is installed.\
This provides an isolated and reproducible testing environment.
