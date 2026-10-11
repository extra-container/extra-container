{
  description = "A container in a WireGuard network namespace";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    extra-container.url = "github:extra-container/extra-container";
    extra-container.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { extra-container, nixpkgs, ... }:
    let
      network = import ./wgnet-settings.nix;
      publicKey = builtins.getEnv "CONTAINER_SSH_KEY";
    in
    {
      nixosModules.wgnet = import ./wgnet.nix;
    }
    // extra-container.lib.eachSupportedSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.just
            pkgs.openssh
            extra-container.packages.${system}.default
          ];
        };
        packages.default = extra-container.lib.buildContainers {
          inherit system nixpkgs;
          config = {
            assertions = [
              {
                assertion = publicKey != "";
                message = "Use just start, or set CONTAINER_SSH_KEY with --impure.";
              }
            ];
            containers.vpn = {
              privateNetwork = false;
              networkNamespace = "/run/netns/${network.namespace}";
              config = { config, pkgs, ... }: {
                system.stateVersion = "26.05";
                networking = {
                  hostName = "vpn";
                  useDHCP = false;
                  enableIPv6 = false;
                  # Interfaces, routes and filtering belong to the host module.
                  firewall.enable = false;
                  resolvconf.enable = false;
                  inherit (network) nameservers;
                };
                environment.etc."resolv.conf".text =
                  builtins.concatStringsSep "\n" (map (ip: "nameserver ${ip}") config.networking.nameservers) + "\n";
                users.users.user = {
                  isNormalUser = true;
                  uid = 1000;
                  group = "users";
                  shell = pkgs.zsh;
                  openssh.authorizedKeys.keys = [ publicKey ];
                };
                programs.zsh.enable = true;
                services.openssh = {
                  enable = true;
                  settings = {
                    PasswordAuthentication = false;
                    KbdInteractiveAuthentication = false;
                    PermitRootLogin = "no";
                  };
                };
                environment.systemPackages = with pkgs; [
                  curl
                  iproute2
                  bind.dnsutils
                  vim
                ];
              };
            };
          };
        };
      }
    );
}
