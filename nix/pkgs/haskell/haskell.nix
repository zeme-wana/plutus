############################################################################
# Builds Haskell packages with Haskell.nix
############################################################################
{ lib
, rPackages
, haskell-nix
, agdaWithStdlib
, gitignore-nix
, z3
, R
, libsodium-vrf
, secp256k1
, compiler-nix-name
, enableHaskellProfiling
  # Whether to set the `defer-plugin-errors` flag on those packages that need
  # it. If set to true, we will also build the haddocks for those packages.
, deferPluginErrors
}:
let
  r-packages = with rPackages; [ R tidyverse dplyr stringr MASS plotly shiny shinyjs purrr ];
  project = haskell-nix.cabalProject' ({ pkgs, ... }: {
    inherit compiler-nix-name;
    # This is incredibly difficult to get right, almost everything goes wrong,
    # see https://github.com/input-output-hk/haskell.nix/issues/496
    src = let root = ../../../.; in
      haskell-nix.haskellLib.cleanSourceWith {
        filter = gitignore-nix.gitignoreFilter root;
        src = root;
        # Otherwise this depends on the name in the parent directory, which reduces caching, and is
        # particularly bad on Hercules, see https://github.com/hercules-ci/support/issues/40
        name = "plutus";
      };
    sha256map = {
      "https://github.com/Quid2/flat.git"."ee59880f47ab835dbd73bea0847dab7869fc20d8" = "1lrzknw765pz2j97nvv9ip3l1mcpf2zr4n56hwlz0rk7wq7ls4cm"; # editorconfig-checker-disable-line
      "https://github.com/input-output-hk/cardano-base"."cc049d7c9b9a0129c15b1355fd1dff9e1a1a551c" = "sha256-Ckbl3QkKOuMkIuTsSIWxWly6NNuhGP53q+nwYyBXzz8="; # editorconfig-checker-disable-line
      "https://github.com/input-output-hk/cardano-crypto.git"."07397f0e50da97eaa0575d93bee7ac4b2b2576ec" = "06sdx5ndn2g722jhpicmg96vsrys89fl81k8290b3lr6b1b0w4m3"; # editorconfig-checker-disable-line
      "https://github.com/input-output-hk/cardano-prelude"."fd773f7a58412131512b9f694ab95653ac430852" = "02jddik1yw0222wd6q0vv10f7y8rdgrlqaiy83ph002f9kjx7mh6"; # editorconfig-checker-disable-line
      "https://github.com/input-output-hk/Win32-network"."3825d3abf75f83f406c1f7161883c438dac7277d" = "19wahfv726fa3mqajpqdqhnl9ica3xmf68i254q45iyjcpj1psqx"; # editorconfig-checker-disable-line
    };
    # Configuration settings needed for cabal configure to work when cross compiling
    # for windows. We can't use `modules` for these as `modules` are only applied
    # after cabal has been configured.
    cabalProjectLocal = lib.optionalString pkgs.stdenv.hostPlatform.isWindows ''
      -- When cross compiling for windows we don't have a `ghc` package, so use
      -- the `plutus-ghc-stub` package instead.
      package plutus-tx-plugin
        flags: +use-ghc-stub

      -- Exlcude test that use `doctest`.  They will not work for windows
      -- cross compilation and `cabal` will not be able to make a plan.
      package prettyprinter-configurable
        tests: False
    '';
    modules = [
      ({ pkgs, ... }: lib.mkIf (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform) {
        packages = {
          # Things that need plutus-tx-plugin
          plutus-benchmark.package.buildable = false;
          plutus-errors.package.buildable = false;
          plutus-tx-plugin.package.buildable = false;
          # Needs agda
          plutus-metatheory.package.buildable = false;
          # These need R
          plutus-core.components.benchmarks.cost-model-test.buildable = lib.mkForce false;
          plutus-core.components.exes.generate-cost-model.buildable = lib.mkForce false;
          # This contains support for doing testing, so we're not interested in cross-compiling it
          plutus-conformance.package.buildable = false;
        };
      })
      ({ pkgs, ... }:
        let
          # Add symlinks to the DLLs used by executable code to the `bin` directory
          # of the components with we are going to run.
          # We should try to find a way to automate this will in haskell.nix.
          symlinkDlls = ''
            ln -s \
              ${pkgs.buildPackages.gcc.cc}/x86_64-w64-mingw32/lib/libgcc_s_seh-1.dll \
              $out/bin/libgcc_s_seh-1.dll
            ln -s \
              ${pkgs.buildPackages.gcc.cc}/x86_64-w64-mingw32/lib/libstdc++-6.dll \
              $out/bin/libstdc++-6.dll
            ln -s \
              ${pkgs.windows.mcfgthreads}/bin/mcfgthread-12.dll \
              $out/bin/mcfgthread-12.dll
          '';
        in
        lib.mkIf (pkgs.stdenv.hostPlatform.isWindows) {
          packages = {
            # Add dll symlinks to the compoents we want to run.
            plutus-core.components.tests.plutus-core-test.postInstall = symlinkDlls;
            plutus-core.components.tests.plutus-ir-test.postInstall = symlinkDlls;
            plutus-core.components.tests.untyped-plutus-core-test.postInstall = symlinkDlls;
            plutus-ledger-api.components.tests.plutus-ledger-api-test.postInstall = symlinkDlls;

            # These three tests try to use `diff` and the following could be used to make
            # the linux version of diff available.  Unfortunately the paths passed to it
            # are windows style.
            # plutus-core.components.tests.plutus-core-test.build-tools =
            #   [ pkgs.buildPackages.diffutils ];
            # plutus-core.components.tests.plutus-ir-test.build-tools =
            #   [ pkgs.buildPackages.diffutils ];
            # plutus-core.components.tests.untyped-plutus-core-test.build-tools =
            #   [ pkgs.buildPackages.diffutils ];
            plutus-core.components.tests.plutus-core-test.buildable = lib.mkForce false;
            plutus-core.components.tests.plutus-ir-test.buildable = lib.mkForce false;
            plutus-core.components.tests.untyped-plutus-core-test.buildable = lib.mkForce false;
          };
        }
      )
      (lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin) {
        packages = {
          # This fails on Darwin with strange errors and I don't know why
          # > Error: C stack usage  17556409549320 is too close to the limit
          # > Fatal error: unable to initialize the JI
          plutus-core.components.exes.generate-cost-model.buildable = lib.mkForce false;
        };
      }
      )
      ({ pkgs, config, ... }: {
        packages = {
          # Packages we just don't want docs for
          plutus-benchmark.doHaddock = false;
          # FIXME: Haddock mysteriously gives a spurious missing-home-modules warning
          plutus-tx-plugin.doHaddock = false;

          # In this case we can just propagate the native dependencies for the build of
          # the test executable, which are actually set up right (we have a
          # build-tool-depends on the executable we need)
          # I'm slightly surprised this works, hooray for laziness!
          plutus-metatheory.components.tests.test1.preCheck =
            let
              cmp = project.hsPkgs.plutus-metatheory.components.tests.test1;
              deps = cmp.executableToolDepends;
            in
            ''PATH=${lib.makeBinPath deps }:$PATH'';
          # FIXME: Somehow this is broken even with setting the path up as above
          plutus-metatheory.components.tests.test2.doCheck = false;
          # plutus-metatheory needs agda with the stdlib around for the custom setup
          # I can't figure out a way to apply this as a blanket change for all the
          # components in the package, oh well
          plutus-metatheory.components.library.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.exes.plc-agda.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.tests.test1.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.tests.test2.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.tests.test3.build-tools = [ agdaWithStdlib ];

          plutus-core.components.benchmarks.update-cost-model = {
            build-tools = r-packages;
            # Seems to be broken on darwin for some reason
            platforms = lib.platforms.linux;
          };

          plutus-core.components.benchmarks.cost-model-test = {
            build-tools = r-packages;
            # Seems to be broken on darwin for some reason
            platforms = lib.platforms.linux;
          };

          # Werror everything. This is a pain, see
          # https://github.com/input-output-hk/haskell.nix/issues/519
          plutus-core.ghcOptions = [ "-Werror" ];
          # FIXME: has warnings in generated code
          #plutus-metatheory.package.ghcOptions = "-Werror";
          plutus-benchmark.ghcOptions = [ "-Werror" ];
          plutus-errors.ghcOptions = [ "-Werror" ];
          plutus-ledger-api.ghcOptions = [ "-Werror" ];
          plutus-tx.ghcOptions = [ "-Werror" ];
          plutus-tx-plugin.ghcOptions = [ "-Werror" ];
          prettyprinter-configurable.ghcOptions = [ "-Werror" ];
          word-array.ghcOptions = [ "-Werror" ];

          # External package settings

          inline-r.ghcOptions = [ "-XStandaloneKindSignatures" ];

          # Honestly not sure why we need this, it has a mysterious unused dependency on "m"
          # This will go away when we upgrade nixpkgs and things use ieee754 anyway.
          ieee.components.library.libs = lib.mkForce [ ];

          # See https://github.com/input-output-hk/iohk-nix/pull/488
          cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ libsodium-vrf ] ];
          cardano-crypto-class.components.library.pkgconfig = lib.mkForce [
            [ libsodium-vrf secp256k1 ]
          ];
        };
      })
    ] ++ lib.optional enableHaskellProfiling {
      enableLibraryProfiling = true;
      enableProfiling = true;
    };
  });

in
project
