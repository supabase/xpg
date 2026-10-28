{
  description = "Develop PostgreSQL core and native extensions";

  nixConfig = {
    extra-substituters = [
      "https://nxpg.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nxpg.cachix.org-1:6HKVOmmG/ptPEogBAJ+zR6kRji5F4uHTNx7EGt7WBh0="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      formatter = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in

        pkgs.nixfmt-tree

      );
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          xpgPkgs = import ./nix/packages.nix { inherit pkgs; };
        in
        xpgPkgs
        // {
          default = xpgPkgs.xpg17;

          xpg12 = xpgPkgs.xpg12;
          xpg13 = xpgPkgs.xpg13;
          xpg14 = xpgPkgs.xpg14;
          xpg15 = xpgPkgs.xpg15;
          xpg16 = xpgPkgs.xpg16;
          xpg17 = xpgPkgs.xpg17;
          xpg18 = xpgPkgs.xpg18;
          xpg19 = xpgPkgs.xpg19;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {

	    nativeBuildInputs = with pkgs; [
                gcc
	        clang
                gnumake
            ];
          };
	}
      );

      apps = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          xpgPkgs = import ./nix/packages.nix { inherit pkgs; };
          mkApp = name: drv: {
            type = "app";
            program = "${drv}/bin/${name}";
          };
        in
        {
          default = mkApp "xpg" xpgPkgs.xpg17;

          xpg12 = mkApp "xpg12" xpgPkgs.xpg12;
          xpg13 = mkApp "xpg13" xpgPkgs.xpg13;
          xpg14 = mkApp "xpg14" xpgPkgs.xpg14;
          xpg15 = mkApp "xpg15" xpgPkgs.xpg15;
          xpg16 = mkApp "xpg16" xpgPkgs.xpg16;
          xpg17 = mkApp "xpg17" xpgPkgs.xpg17;
          xpg18 = mkApp "xpg18" xpgPkgs.xpg18;
          xpg19 = mkApp "xpg19" xpgPkgs.xpg19;

          xpg-core = mkApp "xpg-core" xpgPkgs.xpg-core;
        }
      );
    };
}
