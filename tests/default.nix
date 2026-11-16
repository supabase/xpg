let
  lock = (builtins.fromJSON (builtins.readFile ../flake.lock)).nodes.nixpkgs.locked;
  pkgs = import (builtins.fetchTarball {
    name = lock.rev;
    url = "https://github.com/${lock.owner}/${lock.repo}/archive/${lock.rev}.tar.gz";
    sha256 = lock.narHash;
  }) { };
in
with pkgs;
let
  xpgPkgs = import ../default.nix;
  pgsqlcheck19 = callPackage ../nix/plpgsql-check.nix {
    postgresql = xpgPkgs.postgresql_19;
  };
  postgis19 = callPackage ../nix/postgis.nix {
    postgresql = xpgPkgs.postgresql_19;
  };
in
{
  xpg = xpgPkgs.xpg.withExtensions {
    extensions = {
      "19" = [ pgsqlcheck19 postgis19 ];
    };
  };
}
