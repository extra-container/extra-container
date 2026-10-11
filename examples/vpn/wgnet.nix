# Wireguard vpn namespace. Import on the host.
{ pkgs, ... }:
let
  network = import ./wgnet-settings.nix;
  ns = network.namespace;
  hostInterface = network.hostInterface;
in
{
  boot.kernelModules = [ "wireguard" ];
  systemd.services.wgvpn-vpn = {
    description = "WireGuard namespace for the vpn container";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      iproute2
      wireguard-tools
      nftables
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      test -r ${network.configFile}
      ip netns add ${ns}
      ip -n ${ns} link set lo up
      ip link add ${hostInterface} type veth peer name vpn-peer
      ip link set vpn-peer netns ${ns}
      ip -n ${ns} link set vpn-peer name eth-lan
      ip addr add ${network.hostAddress}/31 dev ${hostInterface}
      ip -n ${ns} addr add ${network.localAddress}/31 dev eth-lan
      ip link set ${hostInterface} up
      ip -n ${ns} link set eth-lan up

      # Born in the host namespace: encrypted UDP uses the host's routes.
      ip link add wg-vpn type wireguard
      ip link set wg-vpn netns ${ns}
      ip -n ${ns} link set wg-vpn name wg0
      ip -n ${ns} addr add ${network.wireguardAddress} dev wg0
      ip netns exec ${ns} wg setconf wg0 ${network.configFile}

      # Install filtering before bringing up the tunnel and default route.
      ip netns exec ${ns} nft -f - <<'NFT'
      table inet vpn {
        chain output {
          type filter hook output priority 0; policy drop;
          oifname "lo" accept
          oifname "wg0" accept
          ct state established,related accept
        }
        chain input {
          type filter hook input priority 0; policy drop;
          iifname "lo" accept
          ct state established,related accept
          iifname "eth-lan" ip saddr ${network.hostAddress} tcp dport 22 accept
          iifname "eth-lan" ip saddr ${network.hostAddress} icmp type echo-request accept
        }
      }
      NFT
      ip -n ${ns} link set wg0 up
      ip -n ${ns} route add default dev wg0
    '';
    preStop = ''
      # Stop the namespace user before removing its interfaces.
      ${pkgs.systemd}/bin/systemctl stop container@vpn.service || true
    '';
    postStop = ''
      # Also runs after partial startup failures. Deleting the veth removes both ends.
      ip link del ${hostInterface} 2>/dev/null || true
      ip link del wg-vpn 2>/dev/null || true
      ip netns del ${ns} 2>/dev/null || true
    '';
  };
}
