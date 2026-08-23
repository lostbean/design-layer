{
  description = "The design-layer gate — renderer, schema, and the checks that decide pass/fail on a design layer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    flake-utils.url = "github:numtide/flake-utils";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # The renderer: the typst binary together with a VENDORED,
        # version-exact package set — every direct and transitive package
        # pinned and present offline, so a render resolves nothing at run time
        # and gives the same result in CI, in a sandbox, and on a laptop.
        # Transitive deps do not resolve on their own: a package importing
        # @preview/oxifmt:0.2.1 needs that exact version listed, or the
        # renderer reaches for the network mid-compile.
        renderer = pkgs.typst.withPackages (
          ps: with ps; [
            cmarker # the markdown bridge
            diagraph # graphviz, as wasm — automatic graph layout
            chronos # sequence diagrams
            finite # state machines
            cetz # the drawing language a native figure may use
            cetz-plot # plots
            fletcher # node-and-edge diagrams, laid out automatically
            lilaq # plots
            showybox # framed blocks
            gentle-clues # admonitions
            codly # code blocks
            timeliney # the pending ledger's time axis
            # Two oxifmt versions, because two cetz versions are in the tree and
            # they disagree. `cetz` here is 0.4.2, which imports oxifmt 1.0.0;
            # `fletcher` pins cetz 0.3.4 internally, which imports oxifmt
            # EXACTLY 0.2.1. withPackages resolves a transitive closure, but
            # measured directly it does NOT carry that second oxifmt: with
            # fletcher alone and the package cache pointed at a nonexistent
            # path, the compile fails on a missing @preview/oxifmt:0.2.1. Both
            # are listed so the render resolves nothing at run time.
            oxifmt_0_2_1
            oxifmt
            tidy
          ]
        );

        # ---------------------------------------------------------------------
        # The gate as a CALLABLE BUNDLE
        # ---------------------------------------------------------------------
        # The design-layer gate is three things that must travel together: the
        # scripts, the ONE declared schema they read their vocabulary from, and
        # the projected renderer library the compile imports. A host repo gets
        # all three by CALLING this flake — it copies nothing. The bundle is
        # one store path holding the scripts, the schema, and a FRESH
        # projection of that schema, so `nix run <this-flake>#check -- <dir>`
        # gates a directory that contains only design-layer files.
        #
        # The projection is built HERE, from the schema in this same source
        # tree. That makes the bundle self-consistent by construction: schema
        # and library can never disagree inside one store path.
        gateBundle =
          pkgs.runCommand "design-gate-bundle"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.python3
              ];
            }
            ''
              cp -r ${./.} repo
              chmod -R u+w repo
              cd repo
              patchShebangs scripts

              mkdir -p "$out/scripts" "$out/schema"
              cp -r scripts/. "$out/scripts/"
              cp schema/design-schema.json "$out/schema/"

              # The projected library, made fresh from the bundled schema.
              bash ./scripts/render-project schema/design-schema.json "$out/render"
            '';

        # The runtime PATH the gate scripts need: bash (render-project and the
        # shell gates), python3 (design-render, design-aggregate,
        # token-coverage, layer-integrity), git (layer-integrity's staleness
        # advisory), and the vendored renderer (the typst compile).
        gateRuntime = [
          pkgs.bash
          pkgs.python3
          pkgs.git
          renderer
        ];

        # One app wrapper per entry point. Every app exports the two variables
        # that let a script find its half of the bundle:
        #
        #   $DESIGN_SCHEMA   the ONE declared schema (already honored by
        #                    design-render and layer-integrity)
        #   $DESIGN_LIB_DIR  the directory holding designlib.typ, so the compile
        #                    imports the BUNDLED library instead of looking for
        #                    a `.render/` inside the target directory
        #
        # Neither variable is overwritten when the caller already set one: a
        # host pointing at its own schema or library keeps that choice.
        #
        # The store is read-only, so nothing is written into $out at run time —
        # the scripts write their scratch and their output under the TARGET
        # directory, which the caller owns.
        gateApp =
          name: script:
          let
            wrapper = pkgs.writeShellApplication {
              inherit name;
              runtimeInputs = gateRuntime;
              text = ''
                export DESIGN_SCHEMA="''${DESIGN_SCHEMA:-${gateBundle}/schema/design-schema.json}"
                export DESIGN_LIB_DIR="''${DESIGN_LIB_DIR:-${gateBundle}/render}"
                exec ${gateBundle}/scripts/${script} "$@"
              '';
            };
          in
          {
            type = "app";
            program = "${wrapper}/bin/${name}";
          };

        # treefmt config — one formatter per language present in this repo.
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true; # Nix (RFC style)
          programs.prettier.enable = true; # Markdown / JSON / YAML
          programs.shfmt.enable = true; # Shell scripts
          programs.ruff-format.enable = true; # Python

          # The gate scripts carry no extension, so each formatter is told
          # which ones are its own. render-project is the only shell one.
          settings.formatter.shfmt.includes = [
            "scripts/render-project"
          ];
          # layer-integrity is a single extensionless python program — it reads
          # each layer file once into an index, which shell could not do without
          # spawning a process per match. Python, so ruff formats it, not shfmt.
          #
          # The other extensionless python programs (design-aggregate,
          # design-render, md-to-typst, token-coverage) are deliberately NOT
          # listed, so treefmt cannot see their language and they go
          # unformatted. Adding them here is a one-line change that rewrites
          # ~320 lines across four files; that reformat is a separate
          # decision from whatever else touches this config, and making it
          # here would bury it in an unrelated diff.
          settings.formatter.ruff-format.includes = [
            "scripts/layer-integrity"
          ];
          settings.global.excludes = [
            # The widget gallery is the renderer-drift TEST FIXTURE, and a
            # figure block's body is VERBATIM Typst which prettier reads as
            # markdown. Measured directly: prettier rewrote
            # `import cetz.draw: *` to `import cetz.draw: \*`, which is invalid
            # Typst, so formatting the fixture broke the render.
            "fixtures/*"
            # A PDF is binary, and a text formatter handed one spends seconds
            # failing to parse it.
            "**/*.pdf"
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.lefthook
            pkgs.poppler-utils # pdftotext, for the self-tests' outline check
            # The treefmt wrapper `nix fmt` resolves to. Putting it in the shell
            # is what makes formatting fast: without it every `nix fmt` call
            # re-evaluates the flake and realises each formatter from the store.
            treefmtEval.config.build.wrapper
            pkgs.shfmt
            pkgs.python3
            # the vendored renderer — the same binary CI and the gate run
            renderer
          ];
        };

        # The bundle itself, buildable: `nix build .#gate-bundle` gives the
        # store path an installer or a CI job can reference directly.
        packages.gate-bundle = gateBundle;
        packages.default = gateBundle;

        # The gate, callable against ANY directory from outside this repo, with
        # nothing copied into that directory.
        #
        #   nix run <flake>#render    -- <design.md> [--check]
        #   nix run <flake>#project   -- <schema.json> <out-dir>
        #   nix run <flake>#aggregate -- <layer-root> <out.pdf>
        #   nix run <flake>#check     -- <layer-root> [repo-root]
        #
        # render, project, and aggregate are thin pass-throughs to one script
        # each. check is the COMPOSITE: the freshness check, token coverage,
        # and layer integrity in sequence.
        apps.render = gateApp "design-render" "design-render";
        apps.project = gateApp "render-project" "render-project";

        # The aggregate, callable on its own. `check` VERIFIES the rendered
        # document (regenerate-and-compare), which presupposes one exists — so a
        # host needs a way to BUILD it the first time, and after every authoring
        # change. That is this app.
        apps.aggregate = gateApp "design-aggregate" "design-aggregate";
        apps.check =
          let
            checkWrapper = pkgs.writeShellApplication {
              name = "design-check";
              runtimeInputs = gateRuntime;
              text = ''
                if [ "$#" -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
                  cat >&2 <<'USAGE'
                usage: design-check <layer-root> [repo-root]

                  <layer-root>  the directory holding the root design.md and the
                                per-context subdirectories (e.g. docs/design)
                  [repo-root]   the repo whose cross-links are checked; defaults
                                to the layer root's grandparent, else the cwd

                Runs, in order: the aggregate freshness check, token coverage,
                and layer integrity. Exit: 0 clean, 1 violation, 2 error.
                USAGE
                  exit 2
                fi

                export DESIGN_SCHEMA="''${DESIGN_SCHEMA:-${gateBundle}/schema/design-schema.json}"
                export DESIGN_LIB_DIR="''${DESIGN_LIB_DIR:-${gateBundle}/render}"

                layer_root="$1"
                shift
                if [ "$#" -ge 1 ]; then
                  repo_root="$1"
                  shift
                else
                  # the layer conventionally sits at <repo>/docs/design, so the
                  # grandparent is the repo; if that shape does not hold, the
                  # cwd is the honest fallback.
                  if repo_root="$(cd "$layer_root/../.." 2>/dev/null && pwd)"; then
                    :
                  else
                    repo_root="$PWD"
                  fi
                fi

                ${gateBundle}/scripts/design-aggregate \
                  "$layer_root" "$layer_root/design-layer.pdf" --check
                ${gateBundle}/scripts/token-coverage "$layer_root"
                ${gateBundle}/scripts/layer-integrity "$repo_root"
              '';
            };
          in
          {
            type = "app";
            program = "${checkWrapper}/bin/design-check";
          };

        # `nix fmt` runs treefmt across the repo.
        formatter = treefmtEval.config.build.wrapper;

        # `nix flake check` verifies everything is formatted.
        checks.formatting = treefmtEval.config.build.check ./.;

        # Every gate script's fixture-based self-test. This is what establishes
        # the correctness of this repo: it holds no design layer of its own, so
        # tests — not dogfooding — are the proof.
        checks.gate-self-tests =
          pkgs.runCommand "gate-self-tests"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.python3
                pkgs.git # layer-integrity's gitignore-prune fixture
                pkgs.poppler-utils # pdftotext — the chapter assertion reads the PDF
                renderer # the render seam
              ];
            }
            ''
              cp -r ${./.} repo
              chmod -R u+w repo
              cd repo
              # The fixtures `git init` throwaway repos; give git a writable
              # HOME and an identity inside the sandbox.
              export HOME="$TMPDIR"
              export GIT_CONFIG_NOSYSTEM=1
              export GIT_AUTHOR_NAME=check GIT_AUTHOR_EMAIL=check@localhost
              export GIT_COMMITTER_NAME=check GIT_COMMITTER_EMAIL=check@localhost
              # The tests exec the gate scripts directly; /usr/bin/env does
              # not exist in the sandbox.
              patchShebangs scripts
              bash ./scripts/layer-integrity.test.sh
              bash ./scripts/widget-coverage.test.sh
              bash ./scripts/design-render.test.sh
              # The offline guarantee, asserted where it is REAL: the build
              # sandbox has no network, so a package the vendored set failed to
              # carry cannot be silently fetched the way it can on a laptop
              # with a warm cache.
              bash ./scripts/vendored-offline.test.sh
              touch $out
            '';

        # The projector is the seam between the ONE declared schema and the
        # renderer library every compile imports. This repo commits no
        # projection — the bundle builds one fresh — so freshness here means
        # something stricter and simpler: the projector RUNS against the
        # committed schema and produces the library the renderer needs. A
        # schema edit that breaks projection fails the flake.
        checks.projection-freshness =
          pkgs.runCommand "projection-freshness"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.python3
              ];
            }
            ''
              cp -r ${./.} repo
              chmod -R u+w repo
              cd repo
              patchShebangs scripts
              fresh="$TMPDIR/projection"
              bash ./scripts/render-project schema/design-schema.json "$fresh"
              if [ ! -f "$fresh/designlib.typ" ]; then
                echo "projection failed: no designlib.typ produced from the schema" >&2
                exit 1
              fi
              # Projecting twice must give the same bytes: the bundle is built
              # by projecting on demand, so a nondeterministic projector would
              # make two bundles of one schema disagree.
              again="$TMPDIR/projection-again"
              bash ./scripts/render-project schema/design-schema.json "$again"
              if ! diff -r "$fresh" "$again" >/dev/null 2>&1; then
                echo "projection is not deterministic: two runs of one schema differ" >&2
                diff -r "$fresh" "$again" >&2 || true
                exit 1
              fi
              echo "projection clean: the schema projects, deterministically"
              touch $out
            '';
      }
    );
}
