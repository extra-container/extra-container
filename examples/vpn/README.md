# WireGuard VPN container

This example creates an extra-container whose outbound network connections go through a wireguard vpn. The host creates a network namespace, a veth pair for SSH, and a WireGuard interface, and the container joins that namespace. If the wireguard connection is not active, no process on the container can make outbound network connections, even to the host.

The `wgnet` module must first be enabled on the host. The module runs a service, `wgnet-vpn.service`, which creates the `nsVpn` namespace required by the container. Its options (`services.wgnet.*`) default to the values in `wgnet-settings.nix`, which the container flake reads too; the simplest way to customize is to edit that file so host and container stay in sync.

WireGuard is created in the host namespace and moved into the container's namespace. Its encrypted UDP socket keeps using the host's network, while the container's default route uses `wg0`. The host can SSH to `10.251.1.1` through the dedicated veth pair (`10.251.1.0/31` on the host).

## Host setup

Use a NixOS host with extra-container enabled as described in the repository README. Import `wgnet.nix` into the host configuration, either directly:

```nix
imports = [ /absolute/path/to/extra-container/examples/vpn/wgnet.nix ];
```

or by importing this example as a flake input and importing its `nixosModules.wgnet`. Then enable it:

```nix
services.wgnet.enable = true;
```

Customize settings in `wgnet-settings.nix`, or override individual `services.wgnet.*` options on the host (namespace, veth addresses, tunnel address, config file path). If you override the namespace or `localAddress` on the host, change `wgnet-settings.nix` and the justfile's `_address` to match.

Create `/etc/extra-container/vpn/wg.conf` on the host, owned by root with mode `0600`. Keep this file outside the repository and the Nix store since it contains a private vpn access key. It is read at service startup using `wg setconf`, and is inaccessible from inside the container.

```ini
[Interface]
PrivateKey = zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz=
# Do not set 'Address', 'DNS', or 'PostUp'; these are set by the module and container.

[Peer]
PublicKey = ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ=
AllowedIPs = 0.0.0.0/0
Endpoint = 100.101.102.104:51820
```

Replace both sample keys and the endpoint IP address and port with your VPN provider's values. In `wgnet-settings.nix`, set `wireguardAddress` to the tunnel address, and `nameservers` to the DNS servers supplied by your vpn provider. If the wg.conf file was downloaded from your provider and contains `Addresses`, `DNS`, or `PostUp`, remove or comment out these lines since they are configured by the module and container. The example supports IPv4; IPv6 is disabled inside the container. The host needs outbound UDP access to the endpoint.

After `nixos-rebuild switch`, the service `wgnet-vpn.service` should be running, and `/run/netns/nsVpn` shows the namespace exists.

## Start the container

```bash
cd examples/vpn
nix develop           # (optionally, start devShell, if extra-container isn't installed on your host)
just                  # list justfile targets
just start            # Start if needed
just ssh              # Start if needed, and connect to the container
just stop             # Stop the container, keeping the namespace available
just destroy          # Remove the container and stop the namespace service
```

The recipes generate a dedicated SSH key under `${XDG_STATE_HOME:-$HOME/.local/state}/extra-container-vpn`. Only its public key enters the Nix configuration. The guest user is `user`, UID 1000, with zsh. SSH host keys are remembered in the same state directory; destroying the container removes its old known-host entry.

After changing `wgnet-settings.nix` or `wgnet.nix`, rebuild the host and restart `wgnet-vpn.service`, then run `just start`. If you change `localAddress`, update `_address` in the justfile too. Restarting the namespace service stops the VPN container before deleting the namespace. Rebuild the host after changing its WireGuard config path; changes to the config file itself need only a service restart.

## Check the tunnel

Inside the SSH session, run:

```bash
ip route
curl --connect-timeout 10 https://ifconfig.me
```

The default route should use `wg0`, and the external address should be the VPN exit address (The same curl command on the host should display a different address!).

On the host, inspect the handshake with:

```bash
sudo ip netns exec nsVpn wg show
```

Namespace filtering allows outbound tunnel traffic and replies to host-initiated connections. It blocks new outbound connections over the veth, including direct access to the host or LAN. SSH remains available if the VPN peer is unreachable; Internet traffic has no fallback route through the veth.
