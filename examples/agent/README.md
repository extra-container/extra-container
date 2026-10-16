# Using extra-container for sandboxed development

This flake creates a NixOS extra-container with a handful of development tools, and selected read/write project folder mounts. You can customize network, firewall, and disk mounts to manage access of the processes inside.

Think of the container as lightweight and ephemeral: easy to destroy, reconfigure, and restart. A user inside the container (by default, "user") has a unique home directory, limited tools, and a list of project folders to mount from the linux host.

## Start and connect

The host needs Linux with systemd, Nix with flakes, and the extra-container host setup described in the repository README. On NixOS, enable `programs.extra-container.enable = true;`. The host must also enable forwarding:

```nix
boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
```

Edit `projects` in `flake.nix` to select the list of writable folders beneath `PROJECT_ROOT` (default: `$HOME/project`). The listed folders must exist. The example initially mounts `$HOME/project/extra-container` at `/home/user/project/extra-container`. The guest user has UID 1000 and group `users` (GID 100); adjust these to match the ownership of your host projects. These mounts are writable, so agent edits change the host files too. The rest of the host home directory is not mounted.

```bash
cd examples/agent
nix develop           # (optionally, start devShell, if extra-container isn't installed on your host)
just                  # list available justfile targets
just start            # Start if needed
just ssh              # Start if needed, and connect to the container
just stop
just destroy
```

Set `PROJECT_ROOT=/absolute/path/to/projects` before running `just` to use a different project root. The recipes generate a dedicated SSH key under `${XDG_STATE_HOME:-$HOME/.local/state}/extra-container-agent`, outside the flake source. Only its public key is passed into the Nix configuration. SSH host keys are remembered there; `just destroy` removes the old container's known-host entry. `--impure` is used only to read the project root and public key from the environment.

The container's home persists across stops and updates, and is removed by `just destroy`. Log into `codex` and `claude` inside the container. Install project-specific toolchains by extending `environment.systemPackages` in this flake. `nix develop` and other commands that build inside the container are unavailable, because the container has no access to the host nix daemon. Enabling `extra.hostNixDaemon` would make the agent's user (UID 1000) a trusted nix user if that UID belongs to a host user in `nix.settings.trusted-users`, which gives the agent root-equivalent access to the host. See the Security section of the main README.

The flake uses the Numtide binary cache used by the agent packages. Nix may ask whether to accept these cache settings on first use.

As configured, **sudo is not installed** and "user" is not in the sudoers group. To get a root shell in the container, run `sudo machinectl shell agent` from the host. Once flake.nix and imports are properly configured, root in the container is very rarely needed.

## Options

### Persistent home dir across destroy

To retain the user's .config, .claude, etc. across destroy & restart, `mkdir -p ./home/user` and add it as a bindMount into `/home/user`. Adjust `.gitignore` to manage which ./home/user folders you want to preserve in vcs.

### Networking: veth pair vs shared bridge

**veth pair per container**

The flake uses a veth pair per container, which has an advantage that no host network change is required before starting your first extra-container. `extra.addressPrefix = "10.251.0"` creates a point-to-point veth connection with host address `10.251.0.1` and container address `10.251.0.2`. `extra.enableWAN = true` adds masquerading for outbound traffic. Host IPv4 forwarding must be enabled. Choose a different prefix for each additional container, avoiding your LAN and VPN subnets.

The host can SSH directly to `10.251.0.2`. Other machines cannot initiate connections without host routes or port forwarding. The container can make outbound connections, including to networks reachable through the host.

**host bridge shared by containers**

Create one bridge on the NixOS host and give each container a unique address on its subnet. Replace `enp1s0` with the host's outbound interface:

```nix
networking.bridges.br-containers.interfaces = [ ];
networking.interfaces.br-containers.ipv4.addresses = [
  { address = "10.252.0.1"; prefixLength = 24; }
];
boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
networking.nat = {
  enable = true;
  externalInterface = "enp1s0";
  internalInterfaces = [ "br-containers" ];
};
```

In `containers.agent`, replace both `extra.*` network assignments with:

```nix
privateNetwork = true;
hostBridge = "br-containers";
localAddress = "10.252.0.2/24";
```

Inside `containers.agent.config`, add:

```nix
networking.defaultGateway = { address = "10.252.0.1"; interface = "eth0"; };
```

Change `_address` in the justfile to `10.252.0.2`. Other containers can use
`10.252.0.3/24`, `10.252.0.4/24`, and so on with the same bridge and gateway.
The host manages NAT once for the shared subnet. Guest firewalls still control
which services other containers can reach; this example opens SSH only.
