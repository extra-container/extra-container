{
  description = "An agent sandbox development container with selected project mounts";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    extra-container.url = "github:extra-container/extra-container";
    extra-container.inputs.nixpkgs.follows = "nixpkgs";
    llm-tools.url = "github:numtide/llm-agents.nix";
    # Keep the tools' own nixpkgs pin so their binary cache can be used.
  };

  outputs =
    { extra-container, nixpkgs, ... }@inputs:
    extra-container.lib.eachSupportedSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        llm-tools = inputs.llm-tools.packages.${system};
        projectRoot = builtins.getEnv "PROJECT_ROOT";
        publicKey = builtins.getEnv "CONTAINER_SSH_KEY";
        # Each folder appears under /home/user/project with the same name.
        projects = [ "extra-container" ];
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
                assertion = projectRoot != "" && publicKey != "";
                message = "Use just start, or set PROJECT_ROOT and CONTAINER_SSH_KEY with --impure.";
              }
            ];
            containers.agent = {
              extra.addressPrefix = "10.251.0";
              extra.enableWAN = true;

              # further protect host:
              # block socket access to host nix daemin, and use overlay fs
              # for /nix/store, so container cannot change host's nix store.
              extra.hostNixDaemon = false;
              extra.overlayStore.enable = true;
              extra.overlayStore.gcRoots.enable = true;

              bindMounts = builtins.listToAttrs (
                map (name: {
                  name = "/home/user/project/${name}";
                  value = {
                    hostPath = "${projectRoot}/${name}";
                    isReadOnly = false;
                  };
                }) projects
              );
              config = { config, pkgs, ... }: {
                system.stateVersion = "26.05";
                networking.hostName = "agent";
                networking.nameservers = [
                  "1.1.1.1"
                  "9.9.9.9"
                ];
                networking.resolvconf.enable = false;
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
                nix.settings.experimental-features = [
                  "nix-command"
                  "flakes"
                ];
                environment.systemPackages = [
                  llm-tools.codex
                  llm-tools.claude-code
                ]
                ++ (with pkgs; [
                  pkg-config

                  curl
                  fd
                  gcc
                  gh
                  git
                  gnumake
                  jq
                  jujutsu
                  just
                  nodejs
                  python3
                  ripgrep
                  tmux
                  vim
                ]);
                environment.variables.EDITOR = "vim";
              };
            };
          };
        };
      }
    );
}
