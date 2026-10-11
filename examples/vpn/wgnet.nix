# WireGuard VPN network namespace for the vpn container. Import on the host and set
# `services.wgnet.enable = true`. Option defaults come from ./wgnet-settings.nix, which the
# container flake reads too; if you override an option here, change the settings file to match
# so the container joins the right namespace.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.wgnet;
  defaults = import ./wgnet-settings.nix;
  ns = cfg.namespace;
  inherit (cfg) hostInterface;
in
{
  options.services.wgnet = {
    enable = lib.mkEnableOption "the WireGuard network namespace for the vpn container";

    namespace = lib.mkOption {
      type = lib.types.str;
      default = defaults.namespace;
      description = "Name of the network namespace the container joins (`/run/netns/<name>`).";
    };

    hostInterface = lib.mkOption {
      type = lib.types.str;
      default = defaults.hostInterface;
      description = "Name of the host end of the veth pair used for SSH into the container.";
    };

    hostAddress = lib.mkOption {
      type = lib.types.str;
      default = defaults.hostAddress;
      description = "Host address of the veth pair (a /31 together with `localAddress`).";
    };

    localAddress = lib.mkOption {
      type = lib.types.str;
      default = defaults.localAddress;
      description = "Container address of the veth pair. The host uses it to SSH in.";
    };

    wireguardAddress = lib.mkOption {
      type = lib.types.str;
      default = defaults.wireguardAddress;
      description = "This client's tunnel address with prefix length, as given by the VPN provider.";
    };

    configFile = lib.mkOption {
      type = lib.types.str;
      default = defaults.configFile;
      description = ''
        Path to the WireGuard config file read with `wg setconf`.
        It contains the private key, so keep it out of the repository and the Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "wireguard" ];

    systemd.services.wgnet-vpn = {
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
        test -r ${cfg.configFile}
        ip netns add ${ns}
        ip -n ${ns} link set lo up
        ip link add ${hostInterface} type veth peer name vpn-peer
        ip link set vpn-peer netns ${ns}
        ip -n ${ns} link set vpn-peer name eth-lan
        ip addr add ${cfg.hostAddress}/31 dev ${hostInterface}
        ip -n ${ns} addr add ${cfg.localAddress}/31 dev eth-lan
        ip link set ${hostInterface} up
        ip -n ${ns} link set eth-lan up

        # Born in the host namespace: encrypted UDP uses the host's routes.
        ip link add wg-vpn type wireguard
        ip link set wg-vpn netns ${ns}
        ip -n ${ns} link set wg-vpn name wg0
        ip -n ${ns} addr add ${cfg.wireguardAddress} dev wg0
        ip netns exec ${ns} wg setconf wg0 ${cfg.configFile}

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
            iifname "eth-lan" ip saddr ${cfg.hostAddress} tcp dport 22 accept
            iifname "eth-lan" ip saddr ${cfg.hostAddress} icmp type echo-request accept
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
  };
}
