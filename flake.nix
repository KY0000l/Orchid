{
  description = "Orchid, an experimental Nintendo Switch 2 emulator";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      rev = self.rev or self.dirtyRev or "unknown";
    in
    {
      # Use in a NixOS or home-manager config:
      #   nixpkgs.overlays = [ orchid.overlays.default ];
      #   environment.systemPackages = [ pkgs.orchid ];
      overlays.default = final: _prev: {
        orchid = final.callPackage ./nix/package.nix { inherit rev; };
        orchid-pgo = final.callPackage ./nix/package.nix {
          inherit rev;
          thinLTO = false;
        };
        orchid-generic = final.callPackage ./nix/package.nix {
          inherit rev;
          pgo = false;
          thinLTO = false;
        };
      };

      packages = forAllSystems (pkgs: rec {
        # ThinLTO + PGO (clang 23, orchid.profdata): maximum performance.
        orchid = pkgs.callPackage ./nix/package.nix { inherit rev; };
        # PGO only. Identical to the release "-pgo" AppImage's configuration.
        orchid-pgo = pkgs.callPackage ./nix/package.nix {
          inherit rev;
          thinLTO = false;
        };
        # Plain Release build with the default stdenv compiler.
        orchid-generic = pkgs.callPackage ./nix/package.nix {
          inherit rev;
          pgo = false;
          thinLTO = false;
        };
        default = orchid;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.orchid}/bin/orchid";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.orchid-generic ];
        };
      });
    };
}
