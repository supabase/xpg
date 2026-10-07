{
  stdenv,
  lib,
  makeWrapper,
  fetchurl,
  writeShellScriptBin,
  findutils,
  entr,
  lcov,
  gnused,
  gdb,
  writeText,
  ourPg,
  checked-shell-script,
  git,
  extensions ? { },
  # PostgreSQL major versions supported by this build of xpg. Every listed
  # version (and its cassert variant, unless `cassert = false`) becomes a
  # runtime dependency of the resulting derivation, so narrowing this list
  # (see `forVersions` in nix/packages.nix) shrinks the closure to just the
  # versions needed.
  versions ? [
    "19"
    "18"
    "17"
    "16"
    "15"
    "14"
    "13"
    "12"
  ],
  # Whether to include the cassert-enabled PostgreSQL builds (and the
  # `--cassert` flag's ability to select them) in this build's closure.
  # Disabling this halves the PostgreSQL closure for consumers (e.g. CI) that
  # never pass `--cassert`.
  cassert ? true,
}:
let
  isLinux = stdenv.isLinux;
  gdbConf = writeText "gdbconf" ''
    # Do this so we can do `backtrace` once a segfault occurs. Otherwise once SIGSEGV is received the bgworker will quit and we can't backtrace.
    handle SIGSEGV stop nopass
  '';
  buildExtPaths = exts: builtins.concatStringsSep ":" (exts ++ [ "$(pwd)/$BUILD_DIR" ]); # also append the local build directory
  extensionsFor =
    version: if builtins.hasAttr version extensions then builtins.getAttr version extensions else [ ];
  # keep 17 as the default version for backwards compatibility, unless it's not included
  defaultVersion = if builtins.elem "17" versions then "17" else builtins.head versions;
  # pg versions older than 15 don't have the regress output
  versionCaseBranch = v: ''
    ${v})
      ${
        if cassert then
          ''
            if [ "$_arg_cassert" = on ]; then
              export PATH=${ourPg."postgresql_${v}_cassert"}/bin:"$PATH"
            else
              export PATH=${ourPg."postgresql_${v}"}/bin:"$PATH"
            fi
          ''
        else
          ''
            if [ "$_arg_cassert" = on ]; then
              echo 'This build of xpg was not built with cassert support.' >&2
              exit 1
            fi
            export PATH=${ourPg."postgresql_${v}"}/bin:"$PATH"
          ''
      }
      ${lib.optionalString (lib.versionAtLeast v "15") "export PG_REGRESS_TESTS=${
        ourPg."postgresql_${v}".regress
      }"}
      _ext_paths=${buildExtPaths (extensionsFor v)}
      ;;
  '';
  xpg =
    checked-shell-script
      {
        name = "xpg";
        docs = "Develop native PostgreSQL extensions";
        args = [
          "ARG_POSITIONAL_SINGLE([operation], [Operation])"
          "ARG_TYPE_GROUP_SET([OPERATION], [OPERATION], [operation], [build,test,test-core,coverage,psql,gdb,pgbench])"
          "ARG_OPTIONAL_SINGLE([version], [v], [PostgreSQL version], [${defaultVersion}])"
          "ARG_OPTIONAL_SINGLE([options], [o], [Options for the database cluster],)"
          "ARG_OPTIONAL_SINGLE([init-options], [], [Options for the initialization of pgbench],)"
          "ARG_OPTIONAL_BOOLEAN([cassert], [], [Use the cassert-enabled PostgreSQL build])"
          "ARG_OPTIONAL_SINGLE([commit], [], [Run the command in a new git worktree and check out <commit>])"
          "ARG_TYPE_GROUP_SET([VERSION], [VERSION], [version], [${builtins.concatStringsSep "," versions}])"
          "ARG_LEFTOVERS([psql arguments])"
        ];
      }
      ''
        export BUILD_DIR="build-$_arg_version/postgresql" # this needs to be exported so external `make` commands pick it up

        registered_trap_cmds=()

        # In Bash only the last `trap` is considered, so we add some util functions to allow us to run multiple traps.
        # shellcheck disable=SC2317,SC2329
        run_traps() {
          local cmd
          for cmd in "''${registered_trap_cmds[@]}"; do
            eval "$cmd"
          done
        }
        add_trap() {
          local cmd="$1"
          registered_trap_cmds+=("$cmd")
        }

        trap run_traps EXIT SIGINT SIGTERM

        if [ -n "$_arg_commit" ]; then
          worktree_tmpdir="$(mktemp -d)"
          add_trap "${git}/bin/git worktree remove -f \"\$worktree_tmpdir\" > /dev/null && rm -rf \"\$worktree_tmpdir\""

          ${git}/bin/git worktree add -f "$worktree_tmpdir" "$_arg_commit" > /dev/null

          cd "$worktree_tmpdir"
        fi

        case "$_arg_version" in
        ${builtins.concatStringsSep "" (map versionCaseBranch versions)}
        esac

        # TODO remove the need for this conditional once we apply the official extension_control_path patch from pg 18
        # PG 18+ includes upstream support for extension_control_path without our backport patch layout.
        if [ "$_arg_version" -ge 18 ]; then
          EXT_CONTROL_PATHS="$_ext_paths"
          EXT_DYNLIB_PATHS="$_ext_paths/lib"
        else
          EXT_CONTROL_PATHS="$_ext_paths/extension"
          EXT_DYNLIB_PATHS="$_ext_paths/lib"
        fi

        pid_file_name="$BUILD_DIR"/bgworker.pid

        # fail fast for gdb command requirement
        if [ "$_arg_operation" == gdb ] && [ ! -e "$pid_file_name" ]; then
            echo 'The background worker is not started. First you have to run "xpg psql".'
            exit 1
        fi

        COVERAGE_INFO=$BUILD_DIR/coverage.info

        # commands that require the build ready
        case "$_arg_operation" in
          test)
            make
            make prefix="$BUILD_DIR" datadir="$BUILD_DIR" libdir="$BUILD_DIR"/lib install TEST=1 1>&2
            ;;

          coverage)
            if [ ! -f "$COVERAGE_INFO" ]; then
              rm -rf "$BUILD_DIR"/*.o "$BUILD_DIR"/*.so
            fi

            make
            make prefix="$BUILD_DIR" datadir="$BUILD_DIR" libdir="$BUILD_DIR"/lib install TEST=1 COVERAGE=1 1>&2
            ;;

          test-core)
            make
            make prefix="$BUILD_DIR" datadir="$BUILD_DIR" libdir="$BUILD_DIR"/lib install TEST_CORE=1 1>&2
            ;;

          gdb)
            # not required here, do nothing
            ;;

          *)
            make
            make prefix="$BUILD_DIR" datadir="$BUILD_DIR" libdir="$BUILD_DIR"/lib install 1>&2
            ;;
        esac

        # commands that require a temp db
        if [ "$_arg_operation" != build ] && [ "$_arg_operation" != gdb ]; then
          tmpdir="$(mktemp -d)"

          export TMPDIR="$tmpdir"
          export PGDATA="$tmpdir"
          export PGHOST="$tmpdir"
          export PGUSER=postgres
          export PGDATABASE=postgres

          add_trap "pg_ctl stop -m i 1>&2 && rm -rf \"\$tmpdir\" && rm -rf \"\$pid_file_name\""

          PGTZ=UTC initdb -A trust --no-locale --encoding=UTF8 --nosync -U "$PGUSER" 1>&2

          init_script=./test/init.sh

          if [ -f $init_script ]; then
            bash $init_script
          fi

          # pgbench should run with a different conf
          if [ "$_arg_operation" != pgbench ]; then
            init_conf=./test/init.conf

            if [ -f $init_conf ]; then
              cp $init_conf "$tmpdir"/init.conf
              sed -i "s|@TMPDIR@|$tmpdir|g" "$tmpdir"/init.conf
            else
              touch "$tmpdir"/init.conf
            fi

            echo "include 'init.conf'" >> "$PGDATA"/postgresql.conf
          fi

          # pg versions older than 16 don't support adding "-c" to initdb to add these options
          # so we just modify the resulting postgresql.conf to avoid an error
          {
            echo "dynamic_library_path='\$libdir:$EXT_DYNLIB_PATHS'"
            echo "extension_control_path='\$system:$EXT_CONTROL_PATHS'"
          } >> "$PGDATA"/postgresql.conf

          options="-F -c listen_addresses=\"\" -k $PGDATA"

          pg_ctl start -o "$options" -o "$_arg_options" 1>&2

          init_file=test/init.sql

          # always create the contrib_regression db, for backwards compat
          # TODO: make this unnecessary
          createdb contrib_regression 1>&2

          # if not psql command just use the contrib_regression database for running the init_file
          # TODO: this should be removed and instead the fixtures should be loaded with `xpg psql -f`
          if [ "$_arg_operation" != psql ]; then

            if [ -f $init_file ] && [ "$_arg_operation" != pgbench ]; then # don't run for the pgbench command, it uses different fixtures
              psql -v ON_ERROR_STOP=1 -f $init_file -d contrib_regression 1>&2
            fi

          else # else use the default postgres db

            # TODO: if psql uses a different database, the init file and the pid file name creation won't work
            if [ -f $init_file ]; then
              psql -v ON_ERROR_STOP=1 -f $init_file 1>&2
            fi

            # create a pid file in case the psql command is used, for later analysis
            bgworker_name=$(grep -oP '^EXTENSION\s*=\s*\K\S+' Makefile || true) # TODO: assumes the bgworker has the same name as the extension on the Makefile

            if [ -n "$bgworker_name" ]; then
              # save pid for future invocation
              # these commands will not err, taking into account that background workers are not always available (like on pure SQL extensions)
              psql -t -c "\o $pid_file_name" -c "select pid from pg_stat_activity where backend_type ilike '%$bgworker_name%'" 2> /dev/null || true
              ${gnused}/bin/sed '/^''$/d;s/[[:blank:]]//g' -i "$pid_file_name" 2> /dev/null || true
            fi
          fi

        fi

        case "$_arg_operation" in
          build)
            # do nothing here as the build already ran
            ;;

          test-core)
            make test-core
            ;;

          test)
            make test
            ;;

          coverage)
            coverage_out_dir=$BUILD_DIR/coverage_html

            make test

            ${lcov}/bin/lcov --capture --directory . --output-file "$COVERAGE_INFO"

            # remove postgres headers on the nix store, otherwise they show on the output
            ${lcov}/bin/lcov --remove "$COVERAGE_INFO" '/nix/*' --output-file "$COVERAGE_INFO" || true

            ${lcov}/bin/lcov --list "$COVERAGE_INFO"
            ${lcov}/bin/genhtml "$COVERAGE_INFO" --output-directory "$coverage_out_dir"

            echo -e "\nTo see the results, visit file://$(pwd)/$coverage_out_dir/index.html on your browser\n"
            ;;

          psql)
            psql "''${_arg_leftovers[@]}"
            ;;

          pgbench)
            init_bench_file=bench/init.sql

            if [ -n "$_arg_init_options" ]; then
              # shellcheck disable=SC2086
              pgbench -i $_arg_init_options
            fi

            if [ -f $init_bench_file ]; then
              psql -v ON_ERROR_STOP=1 -f $init_bench_file 1>&2
            fi

            pgbench "''${_arg_leftovers[@]}"
            ;;

          gdb)

            ${
              if isLinux then
                ''
                  if [ "$EUID" != 0 ]; then
                    echo 'Prefix the command with "sudo", gdb requires elevated privileges to debug processes.'
                    exit 1
                  fi

                  pid=$(cat "$pid_file_name")
                  if [ -z "$pid" ]; then
                    echo "There's no background worker found for the extension."
                    exit 1
                  fi
                  ${gdb}/bin/gdb -x ${gdbConf} -p "$pid" "''${_arg_leftovers[@]}"
                ''
              else
                ''
                  echo 'gdb command only works on Linux'
                  exit 1
                ''
            }
            ;;

          esac
      '';
in
xpg.bin
