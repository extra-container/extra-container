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
