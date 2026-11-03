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
