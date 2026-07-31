{ pkgs }:
let
  ourPg = pkgs.callPackage ./postgresql {
    inherit (pkgs) lib stdenv fetchurl makeWrapper callPackage;
  };
  checked-shell-script = pkgs.callPackage ./checked-shell-script.nix {
    inherit (pkgs) lib;
  };
  mkXpg = args: pkgs.callPackage ./xpg.nix ({
    inherit ourPg checked-shell-script;
  } // args);
  xpg =
    let
      drv = mkXpg { };
    in
    drv // {
      withExtensions = attrs: mkXpg attrs;
      # variant of xpg that only supports the given pg versions, so consumers (like CI jobs
      # testing a single version) don't pull the closure of every pg version.
      # accepts either a plain list of versions, e.g. `xpg.forVersions ["17"]`,
      # or an attrset to also control other options, e.g.
      # `xpg.forVersions { versions = ["17"]; cassert = false; }` to also drop
      # the cassert-enabled builds from the closure.
      forVersions = args: mkXpg (if builtins.isList args then { versions = args; } else args);
    };
in
{
  inherit xpg;
  xpg-core = pkgs.callPackage ./xpg-core.nix {
    inherit ourPg checked-shell-script;
  };
  postgresql_19 = ourPg.postgresql_19;
  postgresql_19_cassert = ourPg.postgresql_19_cassert;
  postgresql_18 = ourPg.postgresql_18;
  postgresql_18_cassert = ourPg.postgresql_18_cassert;
  postgresql_17 = ourPg.postgresql_17;
  postgresql_17_cassert = ourPg.postgresql_17_cassert;
  postgresql_16 = ourPg.postgresql_16;
  postgresql_16_cassert = ourPg.postgresql_16_cassert;
  postgresql_15 = ourPg.postgresql_15;
  postgresql_15_cassert = ourPg.postgresql_15_cassert;
  postgresql_14 = ourPg.postgresql_14;
  postgresql_14_cassert = ourPg.postgresql_14_cassert;
  postgresql_13 = ourPg.postgresql_13;
  postgresql_13_cassert = ourPg.postgresql_13_cassert;
  postgresql_12 = ourPg.postgresql_12;
  postgresql_12_cassert = ourPg.postgresql_12_cassert;
}
