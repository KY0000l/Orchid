# SPDX-License-Identifier: GPL-3.0-or-later
#
# Orchid, built offline inside the Nix sandbox.
#
# Build variants (see flake.nix):
#   pgo = true,  thinLTO = true   clang 23, -fprofile-use=orchid.profdata, -flto=thin  (default)
#   pgo = true,  thinLTO = false  same as the upstream release "-pgo" build
#   pgo = false, thinLTO = false  stdenv compiler, plain Release
{
  lib,
  stdenv,
  llvmPackages_23,
  fetchurl,
  cmake,
  ninja,
  pkg-config,
  python3,
  git,
  jq,
  patch,
  unzip,
  glslang,
  qt6,
  qt6Packages,
  boost,
  fmt,
  lz4,
  nlohmann_json,
  openssl,
  zlib,
  enet,
  libopus,
  vulkan-headers,
  vulkan-utility-libraries,
  vulkan-memory-allocator,
  vulkan-loader,
  spirv-headers,
  spirv-tools,
  simpleini,
  xbyak,
  cubeb,
  cpp-jwt,
  httplib,
  libusb1,
  ffmpeg-headless,
  sdl3,
  gamemode,
  udev,
  wayland,
  libxkbcommon,
  libGL,
  # Release channel number from .github/version (the CI counts the patch up).
  version ? "0.7",
  rev ? "unknown",
  # Profile-guided optimisation using the repo's orchid.profdata.
  pgo ? true,
  # ThinLTO on top of PGO. Set false to match the upstream CI's PGO build exactly.
  thinLTO ? true,
  # One of: custom (no -march), generic, v3, zen2, zen4, native (x86_64 only).
  # "native" makes the result impure and unusable on other CPUs.
  buildPreset ? "custom",
  # Not called `src`: callPackage would fill that from nixpkgs' deprecated `src` alias.
  orchidSrc ? lib.cleanSourceWith {
    src = ../.;
    filter =
      path: _type:
      let
        rel = lib.removePrefix (toString ../. + "/") (toString path);
      in
      !(builtins.elem rel [
        ".git"
        ".github"
        ".forgejo"
        "docs"
        "nix"
        "flake.nix"
        "flake.lock"
      ]);
  },
}:

let
  inherit (qt6Packages) quazip;
  llvm = llvmPackages_23;
  useClang = pgo || thinLTO;
  baseStdenv = if useClang then llvm.stdenv else stdenv;

  # Packages that CPMUtil insists on bundling, or that have no usable system
  # package. CPMUtil would download them at configure time, which the sandbox
  # forbids, so they are fetched here with the exact SHA-512 from cpmfile.json
  # and handed to CMake via <name>_CUSTOM_DIR. Keep these in sync with
  # cpmfile.json when bumping them.
  cpmDep =
    {
      name,
      url,
      hash,
      patchDir ? null,
    }:
    stdenv.mkDerivation {
      pname = "orchid-cpm-${name}";
      version = "0";
      src = fetchurl { inherit url hash; };
      patches = lib.optionals (patchDir != null) (
        map (f: "${orchidSrc}/.patch/${patchDir}/${f}") (
          builtins.attrNames (builtins.readDir "${orchidSrc}/.patch/${patchDir}")
        )
      );
      dontConfigure = true;
      dontBuild = true;
      installPhase = "cp -r . $out";
    };

  deps = {
    sirit = cpmDep {
      name = "sirit";
      url = "https://github.com/eden-emulator/sirit/archive/v1.0.5.tar.gz";
      hash = "sha512-t81ohayuP8hpgojRn+u6DdReSgKitlY9LrmVqYjQhHBG6NFqXep+C/gytDIbzsE0zbr8VT9u3gOeTPNFJcXc5Q==";
      patchDir = "sirit";
    };
    # Always bundled upstream: NUP archives are only byte-identical across
    # builds when every build uses the same zstd.
    zstd = cpmDep {
      name = "zstd";
      url = "https://github.com/facebook/zstd/archive/33618c8.tar.gz";
      hash = "sha512-KwBsPBEMOL0vWJa0LTajiTHI6uJh8wVS+an9BEWNIY2PGhQl8Rf9Eq9UXtdwQuSy0aGptihsTQuddO958gqPCA==";
    };
    # nixpkgs' `frozen` is an unrelated JSON parser, so this one is always fetched.
    frozen = cpmDep {
      name = "frozen";
      url = "https://github.com/serge-sans-paille/frozen/archive/61dce5ae18.tar.gz";
      hash = "sha512-uN/nQcgrwXjfyXSdSrWhMM7nGNnue3HZtUfPX38jAn7QFSrSUAEqhUY5n8weEhh+/GjYnWcxJWxNLffQTu+NXA==";
    };
    zbic = cpmDep {
      name = "zbic";
      url = "https://github.com/kinnay/zbic/archive/11b08f2712264bbed731545085cbd9702096ceb7.tar.gz";
      hash = "sha512-++LzeYY3fX8Nlq4yJMgLWXHfbotpYfaAYfGXXrsujLePB7kPAUsAe+QCPb9VE1gVBOf31hpSN8sqinphrhHkgg==";
    };
    reshade = cpmDep {
      name = "reshade";
      url = "https://github.com/crosire/reshade/archive/v6.8.0.tar.gz";
      hash = "sha512-b8mzmCHKbi2RFg8FhGs6QhWf7HWfXW+6kdGleAGhva9gR3QFeME28LGmCpwprRYNh9v+Db+8326oeaigeDd7jA==";
      patchDir = "reshade";
    };
  };

  # Switch time zone data, passed as YUZU_TZDB_PATH (must contain zoneinfo/).
  tzdb = stdenv.mkDerivation {
    pname = "orchid-nx-tzdb";
    version = "230326";
    src = fetchurl {
      url = "https://git.eden-emu.dev/eden-emu/tzdb_to_nx/releases/download/230326/230326.tar.gz";
      hash = "sha512-zOZaEr+Q9OrUOySguV3613rD2b+6r2bFXmcBNG56HkTKXS8j9H7jXuAicesQgr8XYq8geq2fsjbxyEdoEtAI7Q==";
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      # The archive may or may not wrap everything in one directory.
      if [ -d zoneinfo ]; then root=.; else root=$(dirname "$(find . -type d -name zoneinfo | head -n1)"); fi
      mkdir -p $out
      cp -r "$root"/. $out/
    '';
  };

  profile = "-fprofile-use=${orchidSrc}/orchid.profdata -Wno-backend-plugin -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date";
  commonFlags = lib.concatStringsSep " " (
    lib.optional pgo profile ++ lib.optional thinLTO "-flto=thin"
  );
  linkFlags = lib.concatStringsSep " " (
    lib.optionals useClang [
      "-fuse-ld=lld"
    ]
    ++ lib.optional thinLTO "-flto=thin"
  );
in
baseStdenv.mkDerivation {
  pname = "orchid";
  inherit version;
  src = orchidSrc;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    python3
    git
    jq
    patch
    unzip
    glslang
    qt6.wrapQtAppsHook
    qt6.qttools
  ]
  ++ lib.optionals useClang [
    llvm.lld
    llvm.llvm # llvm-ar / llvm-ranlib for LTO archives
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtcharts
    qt6.qtwayland
    qt6.qt5compat
    quazip
    boost
    fmt
    lz4
    nlohmann_json
    openssl
    zlib
    enet
    libopus
    vulkan-headers
    vulkan-utility-libraries
    vulkan-memory-allocator
    spirv-headers
    spirv-tools
    simpleini
    xbyak
    cubeb
    cpp-jwt
    httplib
    libusb1
    ffmpeg-headless
    sdl3
    gamemode
    udev
    wayland
    libxkbcommon
  ];

  # Version strings come from GIT-* files when there is no .git directory
  # (see externals/cmake-modules/GetSCMRev.cmake).
  postPatch = ''
    printf '%s' "${rev}" > GIT-COMMIT
    printf '%s' "main" > GIT-REFSPEC
    printf '%s' "v${version}" > GIT-TAG
  '';

  cmakeBuildType = "Release";

  cmakeFlags = [
    (lib.cmakeBool "BUILD_TESTING" false)
    (lib.cmakeBool "YUZU_TESTS" false)
    (lib.cmakeBool "YUZU_CMD" true)
    (lib.cmakeBool "YUZU_ROOM" false)
    (lib.cmakeBool "YUZU_ROOM_STANDALONE" false)
    (lib.cmakeBool "ENABLE_UPDATE_CHECKER" false)
    (lib.cmakeBool "USE_DISCORD_PRESENCE" false)
    (lib.cmakeBool "YUZU_DISABLE_LLVM" true)
    (lib.cmakeBool "YUZU_INSTALL_UDEV_RULES" true)
    # Compiler/toolchain upgrades must not break the build over a warning.
    (lib.cmakeBool "ENABLE_WERROR" false)
    (lib.cmakeFeature "YUZU_BUILD_PRESET" buildPreset)

    # Everything comes from nixpkgs, nothing is downloaded.
    (lib.cmakeBool "YUZU_USE_BUNDLED_QT" false)
    (lib.cmakeBool "YUZU_USE_BUNDLED_SDL3" false)
    (lib.cmakeBool "YUZU_USE_BUNDLED_FFMPEG" false)
    (lib.cmakeBool "YUZU_USE_BUNDLED_OPENSSL" false)
    (lib.cmakeBool "CPMUTIL_FORCE_SYSTEM" true)

    # The exceptions, fetched above.
    (lib.cmakeFeature "sirit_CUSTOM_DIR" "${deps.sirit}")
    (lib.cmakeFeature "zstd_CUSTOM_DIR" "${deps.zstd}")
    (lib.cmakeBool "frozen_FORCE_BUNDLED" true)
    (lib.cmakeFeature "frozen_CUSTOM_DIR" "${deps.frozen}")
    (lib.cmakeBool "zbic_FORCE_BUNDLED" true)
    (lib.cmakeFeature "zbic_CUSTOM_DIR" "${deps.zbic}")
    (lib.cmakeBool "reshade_FORCE_BUNDLED" true)
    (lib.cmakeFeature "reshade_CUSTOM_DIR" "${deps.reshade}")
    (lib.cmakeFeature "YUZU_TZDB_PATH" "${tzdb}")
  ]
  ++ lib.optionals useClang [
    (lib.cmakeFeature "CMAKE_AR" "${llvm.llvm}/bin/llvm-ar")
    (lib.cmakeFeature "CMAKE_RANLIB" "${llvm.llvm}/bin/llvm-ranlib")
  ];

  # Passed through the compiler wrapper's environment rather than cmakeFlags:
  # cmakeFlags are split on whitespace, which would turn the individual
  # -W options below into (invalid) CMake arguments.
  env = {
    NIX_CFLAGS_COMPILE = commonFlags;
    NIX_CFLAGS_LINK = linkFlags;
  };

  # The Vulkan loader and the audio/input libraries are dlopen()ed.
  qtWrapperArgs = [
    "--prefix LD_LIBRARY_PATH : ${
      lib.makeLibraryPath [
        vulkan-loader
        libGL
        udev
        libxkbcommon
        wayland
        sdl3
      ]
    }"
  ];

  passthru = { inherit deps tzdb; };

  meta = {
    description = "Experimental Nintendo Switch 2 emulator";
    homepage = "https://github.com/MythosOfs/Orchid";
    license = lib.licenses.gpl3Plus;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "orchid";
  };
}
