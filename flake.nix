{
  description = "Wayle - A Wayland desktop shell with bar, notifications, OSD, wallpaper, and device controls";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    wayle-src = {
      url = "github:wayle-rs/wayle";
      flake = false; # it's not a flake
    };
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils, wayle-src, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustToolchain =
          pkgs.rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rustfmt" "clippy" ];
          };

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        wayleBuildInputs = with pkgs; [
          gtk4
          gtk4-layer-shell
          gtksourceview5
          gdk-pixbuf
          pango
          cairo
          graphene
          glib
          libadwaita

          libpulseaudio
          fftw
          pipewire

          sqlite

          wayland
          wayland-protocols
          libxkbcommon

          udev
          systemd
        ];

        wayle = rustPlatform.buildRustPackage {
          pname = "wayle";
          version = "unstable";

          # 🔽 Use upstream source
          src = wayle-src;

          cargoLock = {
            lockFile = "${wayle-src}/Cargo.lock";
            allowBuiltinFetchGit = true;
          };

          nativeBuildInputs = with pkgs; [
            rustToolchain
            pkg-config
            cmake
            makeWrapper
            libclang
          ];

          buildInputs = wayleBuildInputs;

          LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
          BINDGEN_EXTRA_CLANG_ARGS = "-I${pkgs.glibc.dev}/include";

          doCheck = false;

          postInstall = ''
            mkdir -p $out/share/applications
            mkdir -p $out/share/icons/hicolor/scalable/apps
            mkdir -p $out/lib/systemd/user

            cp resources/com.wayle.settings.desktop $out/share/applications/ 2>/dev/null || true
            cp resources/wayle-settings.svg $out/share/icons/hicolor/scalable/apps/ 2>/dev/null || true
            cp resources/wayle.service $out/lib/systemd/user/ 2>/dev/null || true

            if [ -d resources/icons ]; then
              mkdir -p $out/share/icons
              cp -r resources/icons/* $out/share/icons/ 2>/dev/null || true
            fi

            for bin in $out/bin/*; do
              wrapProgram $bin \
                --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath wayleBuildInputs}"
            done
          '';

          meta = with pkgs.lib; {
            description = "A Wayland desktop shell with bar, notifications, OSD, wallpaper, and device controls";
            homepage = "https://wayle.app";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "wayle";
          };
        };

      in {
        packages.default = wayle;
        packages.wayle = wayle;

        apps.default = flake-utils.lib.mkApp { drv = wayle; };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            rustToolchain
            pkg-config
            cmake
            rust-analyzer
            rustfmt
            clippy
          ];

          buildInputs = wayleBuildInputs;

          shellHook = ''
            export RUST_SRC_PATH="${rustToolchain}/lib/rustlib/src/rust/library"
            echo "Wayle dev shell ($(rustc --version))"
          '';
        };

        formatter = pkgs.nixfmt-classic;
      });
}
