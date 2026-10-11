# wgvpn-vpn settings
{
  namespace = "nsVpn";
  hostInterface = "ve-nsVpn";
  hostAddress = "10.251.1.0";
  localAddress = "10.251.1.1";
  wireguardAddress = "10.2.0.2/32"; # This client's tunnel address.
  nameservers = [ "10.2.0.1" ]; # Provider DNS
  configFile = "/etc/extra-container/vpn/wg.conf";
}
