{
  nixosPath,
  systemConfig,
  legacyInstallDirs,
  system ? builtins.currentSystem,
}:

let
  # A minimal module set for evaluating container configs.
  # This significantly reduces extra-container evaluation overhead (total eval time - container eval time)
  # Compatible with nixpkgs >= 16.09
  baseModules = [
    (nixosPath + "/modules/misc/assertions.nix")
    (nixosPath + "/modules/misc/nixpkgs.nix")
    (nixosPath + "/modules/misc/extra-arguments.nix")
    (nixosPath + "/modules/system/activation/top-level.nix")
    (nixosPath + "/modules/system/etc/etc.nix")
    (nixosPath + "/modules/system/boot/systemd.nix")
    nixosContainerModule
    dummyOptions
  ];

  nixosContainerModule =
    let
      new = nixosPath + "/modules/virtualisation/nixos-containers.nix";
      old = nixosPath + "/modules/virtualisation/containers.nix"; # For nixpkgs < 20.09)
    in
    if builtins.pathExists new then new else old;

  dummyOptions =
    {
      pkgs,
      lib,
      options,
      ...
    }:
    let
      optionValue = default: lib.mkOption { inherit default; };
      dummy = optionValue [ ];
    in
    {
      options = {
        boot.kernel.sysctl = dummy;
        boot.kernelModules = dummy;
        boot.kernelPackages.kernel.version = optionValue "";
        boot.kernelParams = dummy;
        boot.loader.systemd-boot.bootCounting.enable = optionValue false;
        environment.systemPackages = dummy;
        environment.variables = optionValue { };
        i18n.imperativeLocale = optionValue false;
        networking.dhcpcd.denyInterfaces = dummy;
        networking.hosts = dummy;
        networking.extraHosts = dummy;
        networking.proxy.envVars = optionValue { };
        nix.package = optionValue pkgs.nix;
        nix.enable = optionValue true; # added 2026-09-09
        nix.daemon.enable = optionValue true; # host nix daemon socket mount. added 2026-09-09

        # `security` and `services.logrotate` were previously declared as
        # leaf dummies. Newer nixpkgs `systemd.nix` writes to
        # `security.pam.services` and `services.logrotate.settings`, which
        # requires those paths to be submodule prefixes — so declare the
        # specific child options instead. (See issue #40.)
        security.polkit.enable = optionValue false;
        security.pam.services = optionValue { };
        services = {
          dbus = dummy;
          logrotate.settings = optionValue { };
          udev = dummy;
          rsyslogd.enable = optionValue false;
          syslog-ng.enable = optionValue false;
          # systemd.nix's `sshd-vsock@` unit (added for systemd-vmspawn)
          # references config.services.openssh.{enable,package}.
          openssh = {
            enable = optionValue false;
            package = optionValue pkgs.openssh;
          };
        };
        system.activationScripts = dummy;
        system.fsPackages = dummy;
        system.nssDatabases = dummy;
        system.nssModules = dummy;
        system.path = optionValue "";
        system.requiredKernelConfig = dummy;
        system.stateVersion = optionValue (if legacyInstallDirs then "21.11" else "22.05");
        # `system.etc.overlay.enable` is declared by newer nixpkgs's etc.nix
        # (already in baseModules), so it does not need a dummy here.
        # Default to `pkgs.systemd` rather than `pkgs.nixos-init` so this
        # remains valid against older nixpkgs that predate the nixos-init
        # split. The body that reads it is gated on `system.etc.overlay`.
        system.nixos-init.package = optionValue pkgs.systemd;
        systemd.oomd = dummy;
        systemd.user.generators = optionValue { };
        time.timeZone = optionValue null;
        # Read by the `warnings` of nixos-containers.nix (checked since 0.17)
        virtualisation.containers.enable = optionValue false;
        ids.gids.keys = dummy;
        ids.uids.systemd-coredump = dummy;
        ids.gids.systemd-journal = dummy;
        ids.gids.systemd-journal-gateway = dummy;
        ids.uids.systemd-journal-gateway = dummy;
        ids.gids.systemd-network = dummy;
        ids.uids.systemd-network = dummy;
        ids.uids.systemd-resolve = dummy;
        ids.gids.systemd-resolve = dummy;
        users.users.systemd-coredump = dummy;
        users.users.systemd-network.group = dummy;
        users.users.systemd-network.uid = dummy;
        users.users.systemd-resolve.group = dummy;
        users.users.systemd-resolve.uid = dummy;
        users.users.systemd-journal-gateway.group = dummy;
        users.users.systemd-journal-gateway.uid = dummy;
        users.groups.systemd-coredump = dummy;
        users.groups.systemd-network.gid = dummy;
        users.groups.systemd-resolve.gid = dummy;
        users.groups.keys.gid = dummy;
        users.groups.systemd-journal.gid = dummy;
        users.groups.systemd-journal-gateway.gid = dummy;
        users.groups.utmp.name = optionValue "utmp";
      };

      config = {
        systemd.timers = lib.mkForce { };
        systemd.targets = lib.mkForce { };
      }
      // lib.optionalAttrs (options.systemd ? managerEnvironment) {
        systemd.managerEnvironment = lib.mkForce { };
      };
    };

  containerAssert =
    cond: name: msg: value:
    if cond then value else throw "container '${name}': ${msg}'";

  assertNonNull = var: containerAssert (var != null);

  # Paths inside the container used by option `extra.overlayStore`
  overlayUpper = "/nix/.overlay/upper";
  overlayWork = "/nix/.overlay/work";
  # State dir of the container's store. The default, /nix/var/nix, contains
  # the host store's database (bind-mounted read-only), which is the lower store.
  overlayState = "/nix/var/nix-overlay";
  # /nix/var/nix/gcroots is bind-mounted from the host
  overlayGCRootsDir = "/nix/var/nix/gcroots/extra-container-overlay";

  overlayStoreModule =
    containerCfg:
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = containerCfg.extra.overlayStore;
      storeUri =
        "local-overlay://?lower-store=${lib.escapeURL "local?read-only=true"}"
        + "&upper-layer=${overlayUpper}&state=${overlayState}";
      # The overlay is mounted by the container, not by nspawn on the host: with
      # `privateUsers`, only mounts inside the container's user namespace give the
      # upper layer the container's UIDs.
      # Mounts inherited from nspawn are locked, so container root can't unmount the
      # mask of the host daemon socket, but it can unmount this overlay. That only
      # exposes the read-only host store.
      mountOverlay = pkgs.writeShellScript "extra-container-mount-overlay-store" ''
        set -euo pipefail
        export PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.util-linux
          ]
        }
        if grep -qs '^overlay /nix/store overlay .*upperdir=${overlayUpper}' /proc/self/mounts; then
          exit 0
        fi
        mkdir -p ${overlayUpper} ${overlayWork}
        # `userxattr` is required for overlay mounts in user namespaces
        mount -t overlay overlay \
          -o lowerdir=/nix/store,upperdir=${overlayUpper},workdir=${overlayWork},userxattr \
          /nix/store
      '';
      syncGCRoots = pkgs.writeShellScript "extra-container-sync-gcroots" ''
        set -euo pipefail
        export NIX_REMOTE=daemon
        export PATH=${
          lib.makeBinPath [
            config.nix.package
            pkgs.coreutils
            pkgs.findutils
          ]
        }
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        mkdir -p ${overlayGCRootsDir}

        # Live paths of the container store that are not in the upper layer are
        # host store paths
        nix-store --gc --print-live | while IFS= read -r path; do
          name=''${path#/nix/store/}
          [[ -e ${overlayUpper}/$name ]] || printf '%s\n' "$name"
        done | sort -u > "$tmp/live"
        find ${overlayGCRootsDir} -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$tmp/rooted"

        # Add new roots before removing stale ones, so that live paths always have roots
        comm -23 "$tmp/live" "$tmp/rooted" | while IFS= read -r name; do
          ln -sfn "/nix/store/$name" "${overlayGCRootsDir}/$name"
        done
        comm -13 "$tmp/live" "$tmp/rooted" | while IFS= read -r name; do
          rm -f "${overlayGCRootsDir}/$name"
        done
        echo "Rooted $(wc -l < "$tmp/live") host store paths"
      '';
      unitDeps = {
        after = [
          "nix-daemon.socket"
          "nix-daemon.service"
        ];
        wants = [ "nix-daemon.socket" ];
      };
    in
    lib.mkMerge [
      {
        nix.settings.experimental-features = [
          "local-overlay-store"
          "read-only-local-store"
        ];
        # The nix sandbox can't work in nspawn containers: it mounts /proc in a new user
        # namespace, which the kernel refuses because nspawn mounts over parts of /proc.
        nix.settings.sandbox = lib.mkDefault false;
        # The store is set via NIX_REMOTE, not the `store` setting in nix.conf: the
        # daemon would also read that setting, and clients send it to the daemon.
        # `%` starts a specifier in systemd's Environment=
        systemd.services.nix-daemon.environment.NIX_REMOTE =
          builtins.replaceStrings [ "%" ] [ "%%" ]
            storeUri;
        # Root would otherwise use the store directly instead of the daemon
        environment.variables.NIX_REMOTE = "daemon";
        systemd.tmpfiles.rules = [ "d ${overlayState} 0755 root root - -" ];
        systemd.services.extra-container-mount-overlay-store = {
          description = "Mount the container's nix store overlay";
          unitConfig.DefaultDependencies = false;
          after = [ "local-fs.target" ];
          before = [
            "nix-daemon.socket"
            "nix-daemon.service"
            "sysinit.target"
          ];
          requiredBy = [
            "nix-daemon.socket"
            "nix-daemon.service"
          ];
          wantedBy = [ "sysinit.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = mountOverlay;
          };
        };
      }
      (lib.mkIf cfg.gcRoots.enable {
        systemd.services.extra-container-sync-gcroots = unitDeps // {
          description = "Add host GC roots for host store paths used by the container";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = syncGCRoots;
          };
        };
        systemd.timers.extra-container-sync-gcroots = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnActiveSec = cfg.gcRoots.interval;
            OnUnitActiveSec = cfg.gcRoots.interval;
          };
        };
        # Sync when the container stops
        systemd.services.extra-container-sync-gcroots-on-stop = unitDeps // {
          description = "Add host GC roots for host store paths used by the container on shutdown";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = syncGCRoots;
          };
        };
      })
    ];

  extraModule =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    with lib;
    {
      options = {
        containers = mkOption {
          type = types.attrsOf (
            types.submodule (
              { config, name, ... }:
              {
                options = {
                  extra = {
                    addressPrefix = mkOption {
                      type = with types; nullOr str;
                      default = null;
                      description = ''
                        Enable privateNetwork and set
                        hostAddress = <addressPrefix>.1
                        localAddress = <addressPrefix>.2
                      '';
                    };
                    enableWAN = mkOption {
                      type = types.bool;
                      default = false;
                      description = ''
                        Enable WAN access inside the container by rewriting container traffic
                        to use the host's address (NAT).

                        Only active when privateNetwork == true.
                      '';
                    };
                    exposeLocalhost = mkOption {
                      type = types.bool;
                      default = false;
                      description = ''
                        Forward requests from the container's external interface
                        to the container's localhost.
                        Useful to test internal services from outside the container.

                        WARNING: This exposes the container's localhost to all users.
                        Only use in a trusted environment.

                        Only active when privateNetwork == true.
                      '';
                    };
                    firewallAllowHost = mkOption {
                      type = types.bool;
                      default = false;
                      description = ''
                        Always allow connections from the container host.

                        Only active when privateNetwork == true.
                      '';
                    };
                    enableSSH = mkOption {
                      type = types.bool;
                      default = builtins.getEnv ("extraContainerSSH") == "1";
                      description = ''
                        Enable SSH access with an automatically generated key.
                        This enables the 'cssh' command in extra-container shell.

                        Requires privateNetwork == true.
                      '';
                    };
                    hostNixDaemon = mkOption {
                      type = types.bool;
                      default = false;
                      description = ''
                        Give the container access to the host's nix daemon socket.

                        When enabled, any process in the container can connect to the host
                        nix daemon. The daemon identifies clients by their host UID, so unless
                        `privateUsers` is enabled, container UIDs are host UIDs: container root
                        and any container user whose UID matches a host user in
                        `nix.settings.trusted-users` are trusted nix users, which is
                        equivalent to root on the host. Untrusted users can still exploit
                        daemon vulnerabilities (e.g. CVE-2026-110450).

                        When disabled (the default), the socket is masked and nix commands
                        that build or substitute (nix build, nix run, nix develop, nix-shell)
                        fail inside the container. Running packages from the container's
                        configuration is not affected.

                        Without `privateUsers`, root in the container can remove the mask.
                      '';
                    };
                    overlayStore = {
                      enable = mkOption {
                        type = types.bool;
                        default = false;
                        description = ''
                          Run a nix daemon inside the container with a private, writable
                          nix store layered over the host's store.

                          The container mounts an OverlayFS on /nix/store at boot: the host
                          store is the read-only lower layer, and builds and substitutions are
                          written to an upper layer in the container's file system
                          (${overlayUpper}). The host store and the host nix daemon are
                          never modified or contacted. The upper layer persists across
                          container restarts and is deleted by `extra-container destroy`.
                          For ephemeral containers, it is deleted when the container stops.

                          Use with `privateUsers` for isolation from the host. Without it,
                          root in the container is not isolated from the host.

                          This makes nix build, nix run, nix develop and nix-shell work inside
                          the container. Builds run as the container's build users, without the
                          nix sandbox, which doesn't work in nspawn containers: builders can
                          read world-readable files in the container and use its network.

                          Uses the experimental nix store type `local-overlay`, so the nix
                          version used by the container must support it. Nix expects the lower
                          store to only grow while the overlay is in use: paths that the host
                          deletes (by garbage collection) break container store paths that
                          depend on them. See `extra.overlayStore.gcRoots`.

                          Can't be combined with `extra.hostNixDaemon`.
                        '';
                      };
                      gcRoots = {
                        enable = mkOption {
                          type = types.bool;
                          default = true;
                          description = ''
                            Protect host store paths that the container uses from host
                            garbage collection.

                            The container's store reuses host store paths instead of
                            downloading or building them again. When such a path is not part
                            of the container's configuration (e.g. a compiler used by a
                            `nix develop` shell in the container), only the container knows
                            that it is in use, and a host garbage collection can delete it,
                            breaking the container store paths that depend on it.

                            When enabled, a service in the container periodically adds host GC
                            roots for all host store paths that are live in the container's
                            store, and removes roots for paths that are no longer live. The
                            roots are stored in /nix/var/nix/gcroots/per-container/<name> on
                            the host and are deleted by `extra-container destroy`.

                            Disable this for short-lived containers that are destroyed before
                            the host runs garbage collection. A container store that has been
                            broken by host garbage collection can be repaired by destroying and
                            recreating the container.
                          '';
                        };
                        interval = mkOption {
                          type = types.str;
                          default = "5min";
                          description = ''
                            How often GC roots are synchronized, as a systemd time span.
                            Roots are also synchronized when the container stops.
                          '';
                        };
                      };
                    };
                  };
                };

                config = mkMerge [
                  (
                    let
                      prefix = config.extra.addressPrefix;
                    in
                    mkIf (prefix != null) {
                      privateNetwork = true;
                      hostAddress = "${prefix}.1";
                      localAddress = "${prefix}.2";
                    }
                  )
                  # nixos-containers.nix always bind-mounts the host daemon socket.
                  # nspawn applies custom mounts sorted by destination, then by type,
                  # and `--inaccessible` sorts after `--bind`, so this reliably masks it.
                  (mkIf (!config.extra.hostNixDaemon && !config.extra.overlayStore.enable) {
                    extraFlags = [ "--inaccessible=/nix/var/nix/daemon-socket" ];
                  })
                  # The tmpfs (sorted after the bind mount, like `--inaccessible`) masks the
                  # host daemon socket and holds the socket of the container's own daemon.
                  (mkIf config.extra.overlayStore.enable {
                    extraFlags = [ "--tmpfs=/nix/var/nix/daemon-socket" ];
                  })
                  {
                    config = (
                      { pkgs, ... }@moduleArgs:
                      mkMerge [
                        {
                          systemd.services.forward-to-localhost =
                            mkIf (config.extra.exposeLocalhost && config.privateNetwork)
                              {
                                wantedBy = [ "network.target" ];
                                script =
                                  assertNonNull config.localAddress name
                                    ''
                                      option extra.exposeLocalhost requires localAddress to be non-null.
                                    ''
                                    ''
                                      ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.all.route_localnet=1
                                      ${pkgs.iptables}/bin/iptables -w -t nat -I PREROUTING -p tcp \
                                        -d ${config.localAddress} ! --dport 80 -j DNAT --to-destination 127.0.0.1
                                    '';
                              };
                          networking.firewall.extraCommands = mkIf (config.extra.firewallAllowHost && config.privateNetwork) (
                            assertNonNull config.hostAddress name
                              ''
                                option extra.exposeLocalhost requires hostAddress to be non-null.
                              ''
                              ''
                                iptables -w -A nixos-fw -s ${config.hostAddress} -j ACCEPT
                              ''
                          );
                          # Silence system state warning
                          system.stateVersion = lib.mkDefault moduleArgs.config.system.nixos.release;
                        }
                        (mkIf config.extra.overlayStore.enable (overlayStoreModule config moduleArgs))
                        (mkIf config.extra.enableSSH {
                          services.openssh.enable = containerAssert config.privateNetwork name ''
                            option extra.enableSSH requires privateNetwork to be enabled.
                          '' true;
                          users.users.root.openssh.authorizedKeys.keyFiles = [
                            /tmp/extra-container-ssh/key.pub
                          ];
                        })
                      ]
                    );
                  }
                ];
              }
            )
          );
        };
      };

      config = {
        assertions = concatLists (
          mapAttrsToList (name: cfg: [
            {
              assertion = !(cfg.extra.hostNixDaemon && cfg.extra.overlayStore.enable);
              message = "container '${name}': options extra.hostNixDaemon and extra.overlayStore.enable can't both be enabled";
            }
          ]) config.containers
        );

        systemd.services =
          let
            WANContainers = builtins.filter (
              c:
              let
                cfg = config.containers.${c};
              in
              cfg.privateNetwork && cfg.extra.enableWAN
            ) (builtins.attrNames config.containers);
            iptables = "${pkgs.iptables}/bin/iptables";
            serviceCfg =
              c:
              let
                containerAddress = config.containers.${c}.localAddress;
              in
              assertNonNull containerAddress c
                ''
                  option extra.enableWAN requires localAddress to be non-null
                ''
                {
                  preStart = "${iptables} -w -t nat -A POSTROUTING -s ${containerAddress} -j MASQUERADE";
                  postStop = "${iptables} -w -t nat -D POSTROUTING -s ${containerAddress} -j MASQUERADE || true";
                };
          in
          listToAttrs (map (c: nameValuePair "container@${c}" (serviceCfg c)) WANContainers);
      };
    };
  eval = import (nixosPath + "/lib/eval-config.nix") {
    inherit baseModules system;
    modules = [
      extraModule
      systemConfig
    ];
  };

  # NixOS only checks `assertions` and `warnings` when building `system.build.toplevel`.
  # extra-container builds `system.build.etc` instead, so apply the same checks here.
  checkedEtc =
    let
      inherit (eval) config;
      lib = eval.pkgs.lib;
      failed = map (x: x.message) (builtins.filter (x: !x.assertion) config.assertions);
    in
    if failed != [ ] then
      throw "\nFailed assertions:\n${builtins.concatStringsSep "\n" (map (x: "- ${x}") failed)}"
    else
      lib.showWarnings config.warnings config.system.build.etc;
in
eval
// {
  config = eval.config // {
    system = eval.config.system // {
      build = eval.config.system.build // {
        etc = checkedEtc;
      };
    };
  };
}
