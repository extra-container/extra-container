{
  description = "Run declarative NixOS containers without full system rebuilds";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      eachSupportedSystem = flake-utils.lib.eachSystem supportedSystems;
      pkg = pkgs: pkgs.callPackage ./. { pkgSrc = ./.; };
    in
    {
      nixosModules.default =
        { pkgs, ... }:
        {
          environment.systemPackages = [ (pkg pkgs) ];
          boot.extraSystemdUnitPaths = [ "/etc/systemd-mutable/system" ];
        };
      overlays.default = final: prev: { extra-container = pkg final; };

      lib = {
        inherit supportedSystems eachSupportedSystem;

        buildContainers =
          {
            system,
            config,
            nixpkgs ? inputs.nixpkgs,
            legacyInstallDirs ? false,
            addRunner ? true,
          }:
          let
            containers = self.lib.evalContainers {
              inherit
                system
                config
                nixpkgs
                legacyInstallDirs
                ;
            };
            etc = containers.config.system.build.etc;
            withRunner = etc.overrideAttrs (old: {
              name = "container";
              buildCommand =
                old.buildCommand
                + "\n"
                + ''
                  install -D -m700 <(printf '${''
                    #!/usr/bin/env bash
                    if ! type -p extra-container >/dev/null; then
                      >&2 echo "Error: extra-container is not installed"
                      >&2 echo "Docs: https://github.com/extra-container/extra-container?tab=readme-ov-file#install"
                      exit 1
                    fi
                    EXTRA_CONTAINER_ETC=%s exec extra-container "$@"
                  ''}' "$out") $out/bin/container
                '';
            });
          in
          (if addRunner then withRunner else etc)
          // {
            inherit (containers) config;
            inherit (containers.config) containers;
          };

        evalContainers =
          {
            system,
            config,
            nixpkgs ? inputs.nixpkgs,
            legacyInstallDirs ? false,
          }:
          import ./eval-config.nix {
            inherit
              system
              legacyInstallDirs
              ;
            nixosPath = nixpkgs + "/nixos";
            systemConfig = config;
          };
      };

    }
    // (eachSupportedSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (nixpkgs) lib;
      in
      rec {
        packages.default = pkg pkgs;

        # This dev shell allows running the `extra-container` command directly from the local
        # source (./extra-container), for quick edit/test cycles.
        # This only works when `nix develop` is started from the repo root directory.
        devShells.default =
          let
            # Extra PATH, as defined in ./default.nix
            path = lib.makeBinPath (
              with pkgs;
              [
                openssh
                e2fsprogs
              ]
            );
          in
          pkgs.stdenv.mkDerivation {
            name = "shell";
            nativeBuildInputs = [
              pkgs.just
              pkgs.python3
            ];

            shellHook = ''
              PATH="${path}''${PATH:+:}$PATH"

              # Enable calling the local source (./extra-container) with command `extra-container`
              PATH="$(realpath .):$PATH"

              # Use the pinned nixpkgs for building containers when running `extra-container`
              export NIX_PATH="nixpkgs=${nixpkgs}''${NIX_PATH:+:}$NIX_PATH"

              # See comment in ./extra-container for an explanation
              export LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
            '';
          };

        packages = {
          # Run a basic extra-container test in a NixOS VM
          test =
            let
              # The introductory example of README.md, as run by util/test-readme.sh
              readmeExample = pkgs.runCommand "readme-example.sh" { nativeBuildInputs = [ pkgs.python3 ]; } ''
                python3 ${./util/readme.py} extract-example --readme ${./README.md} > $out
              '';
              # The container config of the example: the heredoc passed to `extra-container create`
              readmeDemoConfig =
                let
                  afterHeredocStart = lib.elemAt (lib.splitString "<<'EOF'\n" (builtins.readFile ./README.md)) 1;
                in
                import (builtins.toFile "readme-demo.nix" (lib.head (lib.splitString "\nEOF\n" afterHeredocStart)));
            in
            pkgs.testers.nixosTest {
              name = "extra-container";

              nodes.machine =
                { config, pkgs, ... }:
                {
                  imports = [ self.nixosModules.default ];
                  # Used by testScript to run commands in containers and the README example
                  environment.systemPackages = [
                    pkgs.nixos-container
                    pkgs.curl
                  ];
                  environment.etc."readme-example/example.sh".source = readmeExample;
                  environment.etc."readme-example/shims.sh".source = ./util/readme-shims.sh;
                  # Like systems without ext filesystems and with systemd in stage 1, the
                  # system has no e2fsprogs (chattr), see issue #4
                  system.fsPackages = lib.mkForce [ ];
                  # memorySize = 1024 needed for evaluating the container system
                  # memorySize = 1200 needed to avoid error during boot:
                  #   'agetty[817]: failed to open credentials directory'
                  virtualisation.memorySize = 1200;
                  nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
                  system.stateVersion = config.system.nixos.release;
                  # Pre-build the containers used by testScript
                  system.extraDependencies =
                    let
                      buildContainer =
                        systemConfig:
                        (import ./eval-config.nix {
                          nixosPath = "${nixpkgs}/nixos";
                          legacyInstallDirs = false;
                          inherit system systemConfig;
                        }).config.system.build.etc;
                    in
                    [
                      (buildContainer {
                        containers.test.config.environment.etc.testFile.text = "testSuccess";
                      })
                      (buildContainer {
                        containers.test.extra.hostNixDaemon = true;
                      })
                      # privateUsers can't be tested here: it requires idmapped mounts of
                      # /nix/store, which the VM's overlayfs store doesn't support
                      (buildContainer {
                        containers.test.extra.overlayStore.enable = true;
                      })
                      (buildContainer readmeDemoConfig)
                    ];
                };

              testScript = ''
                # The README example. Issue #4: `destroy` failed to remove the container dir
                # on systems without chattr
                machine.fail("command -v chattr")
                machine.succeed(
                  "bash -euo pipefail -c 'source /etc/readme-example/shims.sh; source /etc/readme-example/example.sh'"
                )
                machine.fail("extra-container list | grep -x demo")
                machine.fail("test -e /var/lib/nixos-containers/demo")

                config = '{ containers.test.config.environment.etc.testFile.text = "testSuccess"; }'
                output = machine.succeed(
                  f"extra-container shell -E '{config}' --run c cat /etc/testFile"
                )
                assert "testSuccess" in output, f"Test failed. Output:\n{output}"

                # The host nix daemon socket is masked by default
                storeInfo = "nix --extra-experimental-features nix-command store info --json --store daemon"
                status, output = machine.execute(f"extra-container shell -E '{config}' --run c {storeInfo}")
                assert status != 0, f"Host nix daemon reachable by default. Output:\n{output}"
                output = machine.succeed(
                  f"extra-container shell -E '{config}' --run c ls -A /nix/var/nix/daemon-socket"
                )
                assert "socket" not in output, f"Host nix daemon socket visible. Output:\n{output}"

                # Option `extra.hostNixDaemon` exposes the socket
                daemonConfig = '{ containers.test.extra.hostNixDaemon = true; }'
                output = machine.succeed(f"extra-container shell -E '{daemonConfig}' --run c {storeInfo}")
                assert "\"trusted\"" in output, f"Host nix daemon not reachable. Output:\n{output}"

                # Option `extra.overlayStore`
                import time
                def run(cmd):
                  return machine.succeed(f"nixos-container run test -- {cmd}").strip()

                # A host store path that is not part of the container config
                machine.succeed(
                  "echo 'derivation { name = \"host-dep\"; system = builtins.currentSystem; "
                  + "builder = \"/bin/sh\"; args = [ \"-c\" \"echo host-dep > $out\" ]; }' > /root/x.nix"
                )
                hostDep = machine.succeed("nix-build /root/x.nix -o /root/x").strip()

                overlayConfig = '{ containers.test.extra.overlayStore.enable = true; }'
                machine.succeed(f"extra-container create -E '{overlayConfig}' --start")
                containerRoot = "/var/lib/nixos-containers/test"

                # Build a path in the container that depends on the host store path.
                # The build records whether it runs in the nix sandbox, where /etc/os-release
                # doesn't exist. The sandbox is disabled in containers (see eval-config.nix).
                machine.succeed(
                  "echo 'derivation { name = \"overlay-test\"; system = builtins.currentSystem; "
                  + f"builder = \"/bin/sh\"; dep = builtins.storePath \"{hostDep}\"; "
                  + "args = [ \"-c\" \"test -e /etc/os-release && s=no || s=yes; echo $dep sandbox=$s > $out\" ]; }' "
                  + f"> {containerRoot}/root/y.nix"
                )
                built = run("nix-build /root/y.nix -o /root/y")
                output = run(f"cat {built}")
                assert output == f"{hostDep} sandbox=no", f"Unexpected build output: {output}"

                # The build output is only in the container's upper layer
                machine.fail(f"test -e {built}")
                machine.fail(f"nix-store --query --hash {built}")
                machine.succeed(f"test -e {containerRoot}/nix/.overlay/upper/{built.removeprefix('/nix/store/')}")

                # GC roots for host store paths used by the container
                hostRoots = "/nix/var/nix/gcroots/per-container/test/extra-container-overlay"
                machine.succeed("rm /root/x")
                start = time.monotonic()
                run("systemctl start extra-container-sync-gcroots.service")
                duration = time.monotonic() - start
                props = run(
                  "systemctl show -p ExecMainStartTimestampMonotonic -p ExecMainExitTimestampMonotonic "
                  + "--value extra-container-sync-gcroots.service"
                ).split()
                serviceDuration = (int(props[1]) - int(props[0])) / 1e6
                rooted = run("journalctl -o cat -u extra-container-sync-gcroots.service --grep Rooted")
                print(f"GC roots sync: {serviceDuration:.2f}s (with nixos-container run: {duration:.2f}s), {rooted}")
                machine.succeed(f"test -L {hostRoots}/{hostDep.removeprefix('/nix/store/')}")
                machine.fail(f"nix-store --delete {hostDep}")
                assert run(f"cat {built}").startswith(hostDep)

                # Destroy removes the upper layer and the GC roots
                machine.succeed("extra-container destroy test")
                machine.fail(f"test -e {containerRoot}")
                machine.fail(f"test -e {hostRoots}")
                machine.succeed(f"nix-store --delete {hostDep}")
              '';
            };

          # Used by apps.vm
          vm =
            (import "${nixpkgs}/nixos" {
              inherit system;
              configuration =
                {
                  config,
                  pkgs,
                  lib,
                  modulesPath,
                  ...
                }:
                with lib;
                {
                  imports = [
                    self.nixosModules.default
                    "${modulesPath}/virtualisation/qemu-vm.nix"
                  ];
                  virtualisation.graphics = false;
                  services.getty.autologinUser = "root";
                  nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
                  system.stateVersion = config.system.nixos.release;
                  documentation.enable = false;
                  # Power off VM when the user exits the shell
                  systemd.services."serial-getty@".preStop = ''
                    echo o >/proc/sysrq-trigger
                  '';
                  # Pre-build a minimal container
                  system.extraDependencies =
                    let
                      basicContainer = import ./eval-config.nix {
                        nixosPath = "${nixpkgs}/nixos";
                        legacyInstallDirs = false;
                        inherit system;
                        systemConfig = { };
                      };
                    in
                    [ basicContainer.config.system.build.etc ];
                };
            }).config.system.build.vm;

          runVM = pkgs.writers.writeBash "run-vm" ''
            set -euo pipefail
            export NIX_DISK_IMAGE=/tmp/extra-container-vm-img
            rm -f $NIX_DISK_IMAGE
            trap "rm -f $NIX_DISK_IMAGE" EXIT

            export QEMU_OPTS="-smp $(nproc) -m 2000"
            ${packages.vm}/bin/run-*-vm
          '';

          debugTest = pkgs.writers.writeBash "run-debug-test" ''
            set -euo pipefail
            export TMPDIR=$(mktemp -d)
            trap "rm -rf $TMPDIR" EXIT

            export QEMU_OPTS="-smp $(nproc) -m 2000"
            ${packages.test.driver}/bin/nixos-test-driver <(
              echo "start_all(); import code; code.interact(local=globals())"
            )
          '';

          updateReadme = pkgs.writers.writeBash "update-readme" ''
            exec ${pkgs.python3}/bin/python3 ./util/readme.py update-usage
          '';

          testReadme = pkgs.writers.writeBash "test-readme" ''
            export PATH=${
              lib.makeBinPath [
                pkgs.python3
                pkgs.curl
              ]
            }:$PATH
            exec bash ./util/test-readme.sh "$@"
          '';
        };

        apps = {
          # Run a NixOS VM where extra-container is installed
          vm = {
            type = "app";
            program = toString packages.runVM;
            meta.description = "Run a NixOS VM with extra-container installed";
          };

          # Run a Python test driver shell inside the test VM
          debugTest = {
            type = "app";
            program = toString packages.debugTest;
            meta.description = "Start a Python test driver shell inside the test VM";
          };

          updateReadme = {
            type = "app";
            program = toString packages.updateReadme;
            meta.description = "Copy the extra-container usage text into README.md";
          };

          testReadme = {
            type = "app";
            program = toString packages.testReadme;
            meta.description = "Run the README example end to end (needs sudo)";
          };
        };

        checks = { inherit (packages) test; };
      }
    ));
}
