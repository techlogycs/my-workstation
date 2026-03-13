{ lib, pkgs, username, homeDirectory, editorCommand, ... }:

let
  cleanupPolicy = {
    downloads = {
      enabled = true;
      path = "${homeDirectory}/Downloads";
      maxAgeDays = 90;
    };
    caches = {
      enabled = true;
      maxAgeDays = 14;
      paths = [
        "${homeDirectory}/.cache"
      ];
    };
  };

  cleanupTargets = lib.concatMapStringsSep "\n" (path: ''    ${lib.escapeShellArg path}'') cleanupPolicy.caches.paths;

  cleanupScript = pkgs.writeShellApplication {
    name = "workstation-auto-clean";
    runtimeInputs = with pkgs; [ coreutils findutils ];
    text = ''
            set -Eeuo pipefail

            clean_old_files() {
              local target="$1"
              local age_days="$2"

              if [[ ! -d "$target" ]]; then
                return 0
              fi

              find "$target" -mindepth 1 \( -type f -o -type l \) -mtime +"$age_days" -print -delete
              find "$target" -mindepth 1 -depth -type d -empty -mtime +"$age_days" -print -delete
            }

            ${lib.optionalString cleanupPolicy.downloads.enabled ''
              clean_old_files ${lib.escapeShellArg cleanupPolicy.downloads.path} ${toString cleanupPolicy.downloads.maxAgeDays}
            ''}

            ${lib.optionalString cleanupPolicy.caches.enabled ''
              cache_targets=(
      ${cleanupTargets}
              )

              for target in "''${cache_targets[@]}"; do
                clean_old_files "$target" ${toString cleanupPolicy.caches.maxAgeDays}
              done
            ''}
    '';
  };

  npmCompatScript = pkgs.writeShellScript "npm" ''
    #!/usr/bin/env bash
    exec ${lib.getExe pkgs.bun} "$@"
  '';

  npxCompatScript = pkgs.writeShellScript "npx" ''
    #!/usr/bin/env bash
    exec ${lib.getExe' pkgs.bun "bunx"} "$@"
  '';

  yarnCompatScript = pkgs.writeShellScript "yarn" ''
    #!/usr/bin/env bash
    exec ${lib.getExe pkgs.bun} "$@"
  '';

  pnpmCompatScript = pkgs.writeShellScript "pnpm" ''
    #!/usr/bin/env bash
    exec ${lib.getExe pkgs.bun} "$@"
  '';
in
{
  home = {
    inherit username homeDirectory;
    stateVersion = "25.05";
  };

  # Enable Home Manager and configure backup behavior for existing dotfiles.
  programs.home-manager.enable = true;
  home-manager.backupFileExtension = "backup";

  # Zsh is configured declaratively so shell behaviour is reproducible and does
  # not depend on post-install curl/bash bootstrap scripts.
  programs.zsh = {
    enable = true;
    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "robbyrussell";
    };
    shellAliases = {
      ll = "ls -lah";
      cargo-release = "CARGO_INCREMENTAL=0 RUSTFLAGS='-C target-cpu=native -C codegen-units=1' cargo build --release";
      go-release = "GOMAXPROCS=$(nproc) go build ./...";
      npm = "bun";
      npx = "bunx";
      yarn = "bun";
      pnpm = "bun";
    };
  };

  home.packages = with pkgs; [
    bun
    github-copilot-cli
    nodejs_24
  ];

  home.sessionVariables = {
    EDITOR = editorCommand;
    VISUAL = editorCommand;
    BUN_INSTALL = "${homeDirectory}/.bun";
    CARGO_HOME = "${homeDirectory}/.local/share/cargo";
    CARGO_TARGET_DIR = "${homeDirectory}/.cache/cargo-target";
    GOCACHE = "${homeDirectory}/.cache/go-build";
    GOMODCACHE = "${homeDirectory}/.cache/go/pkg/mod";
    GOPATH = "${homeDirectory}/.local/share/go";
  };

  home.sessionPath = [
    "${homeDirectory}/.local/bin"
  ];

  home.file.".local/bin/npm" = {
    executable = true;
    source = npmCompatScript;
  };

  home.file.".local/bin/npx" = {
    executable = true;
    source = npxCompatScript;
  };

  home.file.".local/bin/yarn" = {
    executable = true;
    source = yarnCompatScript;
  };

  home.file.".local/bin/pnpm" = {
    executable = true;
    source = pnpmCompatScript;
  };

  home.activation.createBuildCaches = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p \
      "$HOME/.bun" \
      "$HOME/.cache/cargo-target" \
      "$HOME/.cache/go-build" \
      "$HOME/.cache/go/pkg/mod" \
      "$HOME/.local/share/cargo" \
      "$HOME/.local/share/go" \
      "$HOME/.local/bin"
  '';

  systemd.user.services.workstation-auto-clean = {
    Unit.Description = "Clean old files from Downloads and cache directories";
    Service = {
      Type = "oneshot";
      ExecStart = "${cleanupScript}/bin/workstation-auto-clean";
    };
  };

  systemd.user.timers.workstation-auto-clean = {
    Unit.Description = "Run periodic cleanup for Downloads and cache directories";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
      Unit = "workstation-auto-clean.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
