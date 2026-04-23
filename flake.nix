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
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils, wayle-src, ... }:
    let
      # Helper to build wayle for any system
      mkWayle = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rustfmt" "clippy" ];
          };

          rustPlatform = pkgs.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };

          wayleBuildInputs = with pkgs; [
            gtk4 gtk4-layer-shell gtksourceview5 gdk-pixbuf pango cairo graphene glib libadwaita
            libpulseaudio fftw pipewire sqlite wayland wayland-protocols libxkbcommon udev systemd
          ];
        in
        rustPlatform.buildRustPackage {
          pname = "wayle";
          version = "unstable";
          src = wayle-src;

          cargoLock = {
            lockFile = "${wayle-src}/Cargo.lock";
            allowBuiltinFetchGit = true;
          };

          nativeBuildInputs = with pkgs; [
            rustToolchain pkg-config cmake makeWrapper libclang
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
              wrapProgram $bin --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath wayleBuildInputs}"
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
    in
    {
      # NixOS module (use nixosModules.wayle or nixosModules.default)
      nixosModules.wayle = { config, pkgs, lib, ... }:
        let
          cfg = config.programs.wayle;
          waylePkg = self.packages.${pkgs.system}.wayle;
        in
        {
          options.programs.wayle = {
            enable = lib.mkEnableOption "Wayle - A Wayland desktop shell";

            package = lib.mkOption {
              type = lib.types.package;
              default = waylePkg;
              description = "The Wayle package to use.";
            };

            systemd.enable = lib.mkEnableOption "the Wayle systemd user service" // { default = true; };

            extraPackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "Additional packages to add to the Wayle environment";
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ] ++ cfg.extraPackages;

            systemd.user.services.wayle = lib.mkIf cfg.systemd.enable {
              description = "Wayle Wayland Desktop Shell";
              serviceConfig = {
                Type = "simple";
                ExecStart = "${lib.getExe cfg.package}";
                Restart = "on-failure";
                RestartSec = "5";
                Environment = [ "PATH=${lib.makeBinPath [ cfg.package ]}" ];
              };
              wantedBy = [ "graphical-session.target" ];
              partOf = [ "graphical-session.target" ];
              after = [ "graphical-session-pre.target" ];
            };

            systemd.packages = [ cfg.package ];
            services.dbus.packages = [ cfg.package ];
          };
        };

      nixosModules.default = self.nixosModules.wayle;

      # Overlay to add wayle to nixpkgs
      overlays.default = final: prev: {
        wayle = self.packages.${prev.system}.wayle;
      };

      homeManagerModules.wayle = { config, pkgs, lib, ... }:
        let
          cfg = config.programs.wayle;
          waylePkg = self.packages.${pkgs.system}.wayle;
        in
        {
          options.programs.wayle = {
            enable = lib.mkEnableOption "Wayle - A Wayland desktop shell";

            package = lib.mkOption {
              type = lib.types.package;
              default = waylePkg;
              description = "The Wayle package to use.";
            };

            systemd.enable = lib.mkEnableOption "the Wayle systemd user service" // { default = true; };

            extraPackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "Additional packages to add to the Wayle environment";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ] ++ cfg.extraPackages;

            systemd.user.services.wayle = lib.mkIf cfg.systemd.enable {
              Unit.Description = "Wayle Wayland Desktop Shell";
              Service = {
                Type = "simple";
                ExecStart = "${lib.getExe cfg.package}";
                Restart = "on-failure";
                RestartSec = "5";
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };
          };
        };

      homeManagerModules.default = self.homeManagerModules.wayle;
    }
    # Per-system outputs
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        wayle = mkWayle system;
      in
      {
        packages = {
          default = wayle;
          wayle = wayle;
        };

        apps.default = flake-utils.lib.mkApp { drv = wayle; };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            (pkgs.rust-bin.stable.latest.default.override {
              extensions = [ "rust-src" "rustfmt" "clippy" ];
            })
            pkg-config cmake rust-analyzer rustfmt clippy
          ];
          buildInputs = with pkgs; [
            gtk4 gtk4-layer-shell gtksourceview5 gdk-pixbuf pango cairo graphene glib libadwaita
            libpulseaudio fftw pipewire sqlite wayland wayland-protocols libxkbcommon udev systemd
          ];
          shellHook = ''
            export RUST_SRC_PATH="${pkgs.rust-bin.stable.latest.default.override { extensions = [ "rust-src" ]; }}/lib/rustlib/src/rust/library"
            echo "Wayle dev shell"
          '';
        };

        formatter = pkgs.nixfmt-classic;
      });
}
