{
  stdenv,
  lib,
  nixos-container,
  openssh,
  e2fsprogs,
  glibcLocales,
  pkgSrc ? lib.cleanSource ./.,
}:

stdenv.mkDerivation rec {
  pname = "extra-container";
  version = "0.17";

  src = pkgSrc;

  buildCommand = ''
    install -D $src/extra-container $out/bin/extra-container
    patchShebangs $out/bin
    share=$out/share/extra-container
    install $src/eval-config.nix -Dt $share

    # Use existing PATH for systemctl and machinectl.
    # e2fsprogs provides chattr, required by `nixos-container destroy` to remove
    # immutable /var/empty dirs. It's not installed on all NixOS systems (#4).
    scriptPath="export PATH=${
      lib.makeBinPath [
        openssh
        e2fsprogs
      ]
    }:\$PATH"

    sed -i "
      s|evalConfig=.*|evalConfig=$share/eval-config.nix|
      s|LOCALE_ARCHIVE=.*|LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive|
      2i$scriptPath
      2inixosContainer=${nixos-container}/bin
    " $out/bin/extra-container
  '';

  meta = with lib; {
    description = "Run declarative containers without full system rebuilds";
    homepage = "https://github.com/extra-container/extra-container";
    changelog = "https://github.com/extra-container/extra-container/blob/main/CHANGELOG.md";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "extra-container";
  };
}
