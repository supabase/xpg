let

  generic =
    # dependencies
    {
      stdenv,
      lib,
      fetchurl,
      makeWrapper,
      glibc,
      zlib,
      readline,
      openssl,
      icu,
      lz4,
      zstd,
      systemd,
      libossp_uuid,
      pkg-config,
      libxml2,
      tzdata,
      libkrb5,
      replaceVars,
      darwin,
      linux-pam,
      bison,
      flex,
      perl,
      docbook_xml_dtd_45,
      docbook-xsl-nons,
      libxslt,

      # This is important to obtain a version of `libpq` that does not depend on systemd.
      systemdSupport ? lib.meta.availableOn stdenv.hostPlatform systemd && !stdenv.hostPlatform.isStatic,
      enableSystemd ? null,
      gssSupport ? with stdenv.hostPlatform; !isWindows && !isStatic,

      # for postgresql.pkgs
      self,
      newScope,
      buildEnv,

      # source specification
      version,
      hash,
      muslPatches ? { },
      extraPatches ? [ ],
      extraPostPatch ? "",

      # for tests
      testers,
      nixosTests,

      # JIT / assertions
      jitSupport,
      cassertSupport ? false,
      nukeReferences,
      patchelf,
      llvmPackages,

      # PL/Python
      pythonSupport ? false,
      python3,

      # detection of crypt fails when using llvm stdenv, so we add it manually
      # for <13 (where it got removed: https://github.com/postgres/postgres/commit/c45643d618e35ec2fe91438df15abd4f3c0d85ca)
      libxcrypt,
    }@args:
    let
      atLeast = lib.versionAtLeast version;
      olderThan = lib.versionOlder version;
      lz4Enabled = atLeast "14";
      zstdEnabled = atLeast "15";

      systemdSupport' =
        if enableSystemd == null then
          systemdSupport
        else
          (lib.warn "postgresql: argument enableSystemd is deprecated, please use systemdSupport instead." enableSystemd);

      pname = "postgresql";

      stdenv' = if jitSupport then llvmPackages.stdenv else stdenv;
    in
    stdenv'.mkDerivation (finalAttrs: {
      inherit version;
      pname = pname + lib.optionalString jitSupport "-jit" + lib.optionalString cassertSupport "-cassert";

      src = fetchurl {
        url = "mirror://postgresql/source/v${version}/${pname}-${version}.tar.bz2";
        inherit hash;
      };

      outputs = [
        "out"
        "lib"
        "doc"
        "man"
        "regress"
      ];
      setOutputFlags = false; # $out retains configureFlags :-/

      buildInputs = [
        zlib
        readline
        openssl
        libxml2
        icu
      ]
      ++ lib.optionals (olderThan "13") [ libxcrypt ]
      ++ lib.optionals jitSupport [ llvmPackages.llvm ]
      ++ lib.optionals lz4Enabled [ lz4 ]
      ++ lib.optionals zstdEnabled [ zstd ]
      ++ lib.optionals systemdSupport' [ systemd ]
      ++ lib.optionals pythonSupport [ python3 ]
      ++ lib.optionals gssSupport [ libkrb5 ]
      ++ lib.optionals stdenv'.isLinux [ linux-pam ]
      ++ lib.optionals (!stdenv'.isDarwin) [ libossp_uuid ];

      nativeBuildInputs = [
        makeWrapper
        pkg-config
      ]
      ++ lib.optionals jitSupport [
        llvmPackages.llvm.dev
        nukeReferences
        patchelf
      ]
      ++ lib.optionals (atLeast "17") [
        bison
        flex
        perl
        docbook_xml_dtd_45
        docbook-xsl-nons
        libxslt
      ];

      enableParallelBuilding = true;

      __structuredAttrs = true;
      separateDebugInfo = true;

      buildFlags = [ "world" ];

      # cassert builds (17+) come with UBSAN. configure picks CFLAGS up from the
      # environment, and PostgreSQL links via $(CC) $(CFLAGS), so the sanitizer
      # runtime is linked too (NIX_CFLAGS_COMPILE alone would leave
      # __ubsan_handle_* undefined at link time).
      env.CFLAGS =
        ""
        + lib.optionalString cassertSupport "-fsanitize=undefined -fno-sanitize-recover=all -fno-omit-frame-pointer "
        + lib.optionalString (cassertSupport && stdenv.isDarwin) "-fno-sanitize=function"
	+ lib.optionalString (cassertSupport && stdenv'.isLinux) "-fsanitize=address";

      # Makes cross-compiling work when xml2-config can't be executed on the host.
      # Fixed upstream in https://github.com/postgres/postgres/commit/0bc8cebdb889368abdf224aeac8bc197fe4c9ae6
      env.NIX_CFLAGS_COMPILE =
        "-std=c11 "
        + lib.optionalString (olderThan "13") "-I${libxml2.dev}/include/libxml2"
        + (if stdenv.isDarwin then " -Wno-error=implicit-function-declaration" else "");

      configureFlags = [
        "--with-openssl"
        "--with-libxml"
        "--with-icu"
        "--sysconfdir=/etc"
        "--libdir=$(lib)/lib"
        "--with-system-tzdata=${tzdata}/share/zoneinfo"
        "--enable-debug"
        (lib.optionalString systemdSupport' "--with-systemd")
        (if stdenv'.isDarwin then "--with-uuid=e2fs" else "--with-ossp-uuid")
      ]
      ++ lib.optionals lz4Enabled [ "--with-lz4" ]
      ++ lib.optionals zstdEnabled [ "--with-zstd" ]
      ++ lib.optionals gssSupport [ "--with-gssapi" ]
      ++ lib.optionals pythonSupport [ "--with-python" ]
      ++ lib.optionals jitSupport [ "--with-llvm" ]
      ++ lib.optionals cassertSupport [ "--enable-cassert" ]
      ++ lib.optionals stdenv'.isLinux [ "--with-pam" ];

      patches = [
        (
          if atLeast "16" then
            ./patches/relative-to-symlinks-16+.patch
          else
            ./patches/relative-to-symlinks.patch
        )
        ./patches/less-is-more.patch
        ./patches/paths-for-split-outputs.patch
        ./patches/specify_pkglibdir_at_runtime.patch
        ./patches/paths-with-postgresql-suffix.patch

        (replaceVars ./patches/locale-binary-path.patch {
          locale = "${if stdenv.isDarwin then darwin.adv_cmds else lib.getBin stdenv.cc.libc}/bin/locale";
        })

      ]
      ++ extraPatches
      ++ lib.optionals stdenv'.hostPlatform.isMusl (
        # Using fetchurl instead of fetchpatch on purpose: https://github.com/NixOS/nixpkgs/issues/240141
        map fetchurl (lib.attrValues muslPatches)
      )
      ++ lib.optionals stdenv'.isLinux [
        (if atLeast "13" then ./patches/socketdir-in-run-13+.patch else ./patches/socketdir-in-run.patch)
      ];

      installTargets = [ "install-world" ];

      postPatch = ''
        # Hardcode the path to pgxs so pg_config returns the path in $out
        substituteInPlace "src/common/config_info.c" --subst-var out
      ''
      + lib.optionalString jitSupport ''
        # Force lookup of jit stuff in $out instead of $lib
        substituteInPlace src/backend/jit/jit.c --replace pkglib_path \"$out/lib\"
        substituteInPlace src/backend/jit/llvm/llvmjit.c --replace pkglib_path \"$out/lib\"
        substituteInPlace src/backend/jit/llvm/llvmjit_inline.cpp --replace pkglib_path \"$out/lib\"
      ''
      + extraPostPatch;

      postInstall = ''
        # install-world does not install this test helper, but we need it for the core regress tests
        if [ -e "src/test/regress/regress${stdenv'.hostPlatform.extensions.sharedLibrary}" ]; then
          install -Dm755 \
            "src/test/regress/regress${stdenv'.hostPlatform.extensions.sharedLibrary}" \
            "$regress/lib/regress${stdenv'.hostPlatform.extensions.sharedLibrary}"
        fi

        # install-world also skips these SPI regression helpers, but some regress suites load them directly
        for spi_helper in autoinc refint; do
          if [ -e "contrib/spi/$spi_helper${stdenv'.hostPlatform.extensions.sharedLibrary}" ]; then
            install -Dm755 \
              "contrib/spi/$spi_helper${stdenv'.hostPlatform.extensions.sharedLibrary}" \
              "$regress/lib/$spi_helper${stdenv'.hostPlatform.extensions.sharedLibrary}"
          fi
        done

        install -d "$regress"
        cp -r \
          src/test/regress/data \
          src/test/regress/expected \
          src/test/regress/sql \
          "$regress/"
        install -Dm644 src/test/regress/parallel_schedule "$regress/parallel_schedule"

        moveToOutput "lib/pgxs" "$out" # looks strange, but not deleting it
        moveToOutput "lib/libpgcommon*.a" "$out"
        moveToOutput "lib/libpgport*.a" "$out"
        moveToOutput "lib/libecpg*" "$out"

        # Prevent retained references to gcc-wrapper in PGXS tool variables.
        substituteInPlace "$out/lib/pgxs/src/Makefile.global" \
          --replace ${stdenv'.cc}/bin/ ""

        if [ -z "''${dontDisableStatic:-}" ]; then
          # Remove static libraries in case dynamic are available.
          for i in $out/lib/*.a $lib/lib/*.a; do
            name="$(basename "$i")"
            ext="${stdenv'.hostPlatform.extensions.sharedLibrary}"
            if [ -e "$lib/lib/''${name%.a}$ext" ] || [ -e "''${i%.a}$ext" ]; then
              rm "$i"
            fi
          done
        fi
      ''
      + lib.optionalString jitSupport ''
        # Move the bitcode and libllvmjit.so library out of $lib; otherwise, every client that
        # depends on libpq.so will also have libLLVM.so in its closure too, bloating it
        moveToOutput "lib/bitcode" "$out"
        moveToOutput "lib/llvmjit*" "$out"

        # In the case of JIT support, prevent a retained dependency on clang-wrapper
        substituteInPlace "$out/lib/pgxs/src/Makefile.global" --replace ${stdenv'.cc}/bin/clang clang
        nuke-refs $out/lib/llvmjit_types.bc $(find $out/lib/bitcode -type f)

        # Stop out depending on the default output of llvm
        substituteInPlace $out/lib/pgxs/src/Makefile.global \
          --replace ${llvmPackages.llvm.out}/bin "" \
          --replace '$(LLVM_BINPATH)/' ""

        # Stop out depending on the -dev output of llvm
        substituteInPlace $out/lib/pgxs/src/Makefile.global \
          --replace ${llvmPackages.llvm.dev}/bin/llvm-config llvm-config \
          --replace -I${llvmPackages.llvm.dev}/include ""

        ${lib.optionalString (!stdenv'.isDarwin) ''
          # Stop lib depending on the -dev output of llvm
          rpath=$(patchelf --print-rpath $out/lib/llvmjit.so)
          nuke-refs -e $out $out/lib/llvmjit.so
          # Restore the correct rpath
          patchelf $out/lib/llvmjit.so --set-rpath "$rpath"
        ''}
      '';

      postFixup = lib.optionalString (!stdenv'.isDarwin && stdenv'.hostPlatform.libc == "glibc") ''
        # initdb needs access to "locale" command from glibc.
        wrapProgram $out/bin/initdb --prefix PATH ":" ${glibc.bin}/bin
      '';

      doCheck = false;
      # autodetection doesn't seem to able to find this, but it's there.
      checkTarget = "check";

      # PG 19+ embeds additional tool paths in installed artifacts, so keep the
      # stricter gcc-wrapper reference check only for older versions for now.
      # Sanitizer builds are exempt: on darwin the clang wrapper bakes an LC_RPATH
      # to its resource-root (where the ubsan runtime lives) into every binary.
      disallowedReferences =
        lib.optionals (lib.versionOlder (lib.versions.major version) "19" && !cassertSupport)
          [
            stdenv'.cc
          ];

      passthru =
        let
          this = self.callPackage generic args;
          jitToggle = this.override {
            jitSupport = !jitSupport;
          };
          cassertToggle = this.override {
            cassertSupport = !cassertSupport;
          };
        in
        {
          psqlSchema = lib.versions.major version;

          withJIT = if jitSupport then this else jitToggle;
          withoutJIT = if jitSupport then jitToggle else this;

          withCassert = if cassertSupport then this else cassertToggle;
          withoutCassert = if cassertSupport then cassertToggle else this;

          dlSuffix = if olderThan "16" then ".so" else stdenv.hostPlatform.extensions.sharedLibrary;

          pkgs =
            let
              scope = {
                inherit jitSupport;
                inherit cassertSupport;
                inherit (llvmPackages) llvm;
                postgresql = this;
                stdenv = stdenv';
              };
              newSelf = self // scope;
              newSuper = {
                callPackage = newScope (scope // this.pkgs);
              };
            in
            import ./ext newSelf newSuper;

          withPackages = postgresqlWithPackages {
            inherit makeWrapper buildEnv;
            postgresql = this;
          } this.pkgs;

          tests = {
            postgresql-wal-receiver = import ../../../../nixos/tests/postgresql-wal-receiver.nix {
              inherit (stdenv) system;
              pkgs = self;
              package = this;
            };
            pkg-config = testers.testMetaPkgConfig finalAttrs.finalPackage;
          }
          // lib.optionalAttrs jitSupport {
            postgresql-jit = import ../../../../nixos/tests/postgresql-jit.nix {
              inherit (stdenv) system;
              pkgs = self;
              package = this;
            };
          };
        };

      meta = with lib; {
        homepage = "https://www.postgresql.org";
        description = "Powerful, open source object-relational database system";
        license = licenses.postgresql;
        changelog = "https://www.postgresql.org/docs/release/${finalAttrs.version}/";
        maintainers = with maintainers; [
          thoughtpolice
          danbst
          globin
          ivan
          ma27
          wolfgangwalther
        ];
        pkgConfigModules = [
          "libecpg"
          "libecpg_compat"
          "libpgtypes"
          "libpq"
        ];
        platforms = platforms.unix;

        # JIT support doesn't work with cross-compilation. It is attempted to build LLVM-bytecode
        # (`%.bc` is the corresponding `make(1)`-rule) for each sub-directory in `backend/` for
        # the JIT apparently, but with a $(CLANG) that can produce binaries for the build, not the
        # host-platform.
        #
        # I managed to get a cross-build with JIT support working with
        # `depsBuildBuild = [ llvmPackages.clang ] ++ buildInputs`, but considering that the
        # resulting LLVM IR isn't platform-independent this doesn't give you much.
        # In fact, I tried to test the result in a VM-test, but as soon as JIT was used to optimize
        # a query, postgres would coredump with `Illegal instruction`.
        broken =
          (jitSupport && stdenv.hostPlatform != stdenv.buildPlatform)
          # Allmost all tests fail FATAL errors for v12 and v13
          || (jitSupport && stdenv.hostPlatform.isMusl && olderThan "14");
      };
    });

  postgresqlWithPackages =
    {
      postgresql,
      makeWrapper,
      buildEnv,
    }:
    pkgs: f:
    buildEnv {
      name = "postgresql-and-plugins-${postgresql.version}";
      paths = f pkgs ++ [
        postgresql
        postgresql.lib
        postgresql.man # in case user installs this into environment
      ];
      nativeBuildInputs = [ makeWrapper ];

      # We include /bin to ensure the $out/bin directory is created, which is
      # needed because we'll be removing the files from that directory in postBuild
      # below. See #22653
      pathsToLink = [
        "/"
        "/bin"
      ];

      # Note: the duplication of executables is about 4MB size.
      # So a nicer solution was patching postgresql to allow setting the
      # libdir explicitly.
      postBuild = ''
        mkdir -p $out/bin
        rm $out/bin/{pg_config,postgres,pg_ctl}
        cp --target-directory=$out/bin ${postgresql}/bin/{postgres,pg_config,pg_ctl}
        wrapProgram $out/bin/postgres --set NIX_PGLIBDIR $out/lib
      '';

      passthru.version = postgresql.version;
      passthru.psqlSchema = postgresql.psqlSchema;
    };

in
# passed by <major>.nix
versionArgs:
# passed by default.nix
{ self, ... }@defaultArgs:
self.callPackage generic (defaultArgs // versionArgs)
