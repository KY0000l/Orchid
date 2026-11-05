# Building and installing with Nix

Orchid ships a flake. Nix builds it offline in the sandbox: system libraries come from nixpkgs, and the few
dependencies CPMUtil insists on bundling (sirit, zstd, zbic, reshade, the Switch time zone data) are fetched
with the SHA-512 hashes from `cpmfile.json`. Nothing is downloaded during configure.

## Packages

| Attribute         | Compiler        | Optimisation                                         |
|-------------------|-----------------|------------------------------------------------------|
| `orchid` (default)| clang 23 + lld  | PGO with `orchid.profdata` + ThinLTO                 |
| `orchid-pgo`      | clang 23 + lld  | PGO only, same configuration as the release `-pgo`   |
| `orchid-generic`  | stdenv compiler | plain Release                                        |

`orchid.profdata` was written by LLVM 23.x and cannot be read by older clang, which is why the PGO
variants use `llvmPackages_23`.

## Try it

```
nix run github:MythosOfs/Orchid
nix build github:MythosOfs/Orchid#orchid-pgo
```

## NixOS / home-manager

```nix
# flake.nix
{
  inputs.orchid.url = "github:MythosOfs/Orchid";
  # inputs.orchid.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, orchid, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        { nixpkgs.overlays = [ orchid.overlays.default ]; }
        ({ pkgs, ... }: {
          environment.systemPackages = [ pkgs.orchid ];
          # Gyro / hidraw access:
          services.udev.packages = [ pkgs.orchid ];
        })
      ];
    };
  };
}
```

Or without the overlay: `environment.systemPackages = [ orchid.packages.${pkgs.system}.default ];`.

## Overrides

```nix
pkgs.orchid.override {
  thinLTO = false;        # PGO only
  buildPreset = "v3";     # custom, generic, v3, zen2, zen4, native
}
```

## Updating dependencies

When `cpmfile.json` changes the version or hash of `sirit`, `zstd`, `zbic`, `reshade` or `tzdb`, update the
matching URL and `hash` in `nix/package.nix` (SRI form: `sha512-` + base64 of the hex digest). When the
`orchid.profdata` is regenerated with a newer LLVM, switch `llvmPackages_23` to the matching version.

## Development shell

`nix develop` gives the build dependencies; then use the usual CMake commands. `shell.nix` remains for
non-flake users.
