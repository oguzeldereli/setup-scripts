#!/usr/bin/env bash
# UCL Programming Tutor Scheme 2026-27 - environment setup for macOS
#
# Usage (in Terminal):
#   bash setup-macos.sh                  # asks which languages you need
#   bash setup-macos.sh --all            # Python, C, Java and Haskell
#   bash setup-macos.sh --dry-run --all  # only show what would be installed; changes nothing
#
# Run "bash setup-macos.sh --help" for all options.
#
# What this script will and will not do:
#   * it only INSTALLS software; it never upgrades or removes anything you already have
#     (anything already installed is skipped, and Homebrew is told not to upgrade existing packages)
#   * it only ADDS lines to ~/.zprofile, and only if they are not already there
#   * it only deletes files inside ~/ucl-code/setup-test, a folder it creates for its own tests
#   * downloads come only from Apple, Homebrew, Microsoft (VS Code), python.org, Adoptium (Java),
#     haskell.org (GHCup) and GitHub (GitHub Desktop)
# Everything printed is also appended to ~/ucl-setup-log.txt. If something fails, show that file to a tutor.

set -uo pipefail

JAVA_VERSION="${JAVA_VERSION:-21}"
WANT_JAVA=""; WANT_HASKELL=""; WANT_GHD=""; ASKED_LANGS=""; ASKED_GHD=""
SKIP_GIT_CONFIG=""
DRY_RUN=""
LOG="$HOME/ucl-setup-log.txt"
TEST_DIR="$HOME/ucl-code/setup-test"
VSCODE_APP="/Applications/Visual Studio Code.app"
GHD_APP="/Applications/GitHub Desktop.app"

usage() {
  cat <<'EOF'
Usage: bash setup-macos.sh [options]

  --java                 install the Eclipse Temurin JDK
  --haskell              install GHCup, GHC, Cabal and HLS
  --all                  install everything (Python, C, Java, Haskell)
  --c, --python          accepted for consistency; Python, C and Git are always installed
  --github-desktop       also install GitHub Desktop (otherwise you are asked)
  --no-github-desktop    do not install or ask about GitHub Desktop
  --java-version N       JDK major version (default: 21)
  --skip-git-config      do not ask for your Git name and email
  --dry-run              print what would be installed without installing or changing anything;
                         then run the tests (they only write inside ~/ucl-code/setup-test)
  -h, --help             show this help

With no language options you are asked which ones you need.
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --c|--python) ASKED_LANGS=1 ;;
    --java) WANT_JAVA=1; ASKED_LANGS=1 ;;
    --haskell) WANT_HASKELL=1; ASKED_LANGS=1 ;;
    --all) WANT_JAVA=1; WANT_HASKELL=1; ASKED_LANGS=1 ;;
    --github-desktop) WANT_GHD=1; ASKED_GHD=1 ;;
    --no-github-desktop) WANT_GHD=""; ASKED_GHD=1 ;;
    --java-version)
      shift
      case "${1:-}" in
        ''|*[!0-9]*) echo "--java-version needs a number, e.g. --java-version 21"; exit 1 ;;
      esac
      JAVA_VERSION="$1" ;;
    --skip-git-config) SKIP_GIT_CONFIG=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
  esac
  shift
done

# ---------- output helpers ----------
if [ -t 1 ]; then
  BOLD=$'\e[1m'; GREEN=$'\e[32m'; RED=$'\e[31m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; DIM=$'\e[2m'; RESET=$'\e[0m'
else
  BOLD=""; GREEN=""; RED=""; YELLOW=""; BLUE=""; DIM=""; RESET=""
fi
step() { printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$*" "$RESET"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s    ! %s%s\n' "$YELLOW" "$*" "$RESET"; }
fail() { printf '%s    x %s%s\n' "$RED" "$*" "$RESET"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Every command that changes the system goes through run (or run_sh for pipelines),
# so it is printed first and skipped in --dry-run mode.
run() {
  printf '%s    $ %s%s\n' "$DIM" "$*" "$RESET"
  [ -n "$DRY_RUN" ] && return 0
  "$@"
}
run_sh() {
  printf '%s    $ %s%s\n' "$DIM" "$1" "$RESET"
  [ -n "$DRY_RUN" ] && return 0
  /bin/bash -c "$1"
}
done_msg() { [ -z "$DRY_RUN" ] && info "$*"; return 0; }

# Reads from the terminal even when the script is piped into bash.
ask_yes_no() {
  local reply=""
  read -r -p "    $1 [y/N] " reply </dev/tty || reply=""
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Adds a line to a file in your home folder unless it is already there. Never rewrites existing content.
append_once() {  # file, line
  if [ -f "$1" ] && grep -qxF "$2" "$1"; then return 0; fi
  printf '%s    + add to %s: %s%s\n' "$DIM" "$1" "$2" "$RESET"
  [ -n "$DRY_RUN" ] && return 0
  printf '\n%s\n' "$2" >> "$1"
}

# Downloads a .zip of a .app and copies the app into /Applications (only if it is not there yet).
install_app_zip() {  # url, app-path, label
  local tmp
  tmp="$(mktemp -d)"
  if run curl -fL --progress-bar -o "$tmp/app.zip" "$1" && run ditto -x -k "$tmp/app.zip" /Applications; then
    done_msg "$3 installed in Applications."
  else
    fail "$3 download failed."
    return 1
  fi
}

RESULTS=()
record() { RESULTS+=("$1|$2|$3"); }  # status|name|detail

# Homebrew: never upgrade things that are already installed.
export HOMEBREW_NO_INSTALL_UPGRADE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_ENV_HINTS=1

brew_formula() {  # formula
  if brew list --formula "$1" >/dev/null 2>&1; then info "$1 already installed (not upgraded)."; return 0; fi
  run brew install "$1"
}

# ---------- preflight ----------
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is for macOS. Use setup-linux.sh on Linux or setup-windows.cmd on Windows."
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "Please run this script as your normal user, not with sudo. It will ask for your password when needed."
  exit 1
fi

{ echo; echo "===== setup-macos.sh $(date) ====="; } >>"$LOG"
exec > >(tee -a "$LOG") 2>&1

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
case "$(uname -m)" in
  arm64) ARCH=aarch64; GHD_ARCH=darwin-arm64; BREW_PREFIX=/opt/homebrew ;;
  *)     ARCH=x64;     GHD_ARCH=darwin;       BREW_PREFIX=/usr/local ;;
esac

printf '%s\n' "${BOLD}UCL Programming Tutor Scheme - macOS setup${RESET}"
info "System: macOS $MACOS_VERSION ($(uname -m))"
info "Log file: $LOG"
[ -n "$DRY_RUN" ] && warn "DRY RUN: commands are printed but nothing is installed or changed."

if [ -z "$ASKED_LANGS" ]; then
  step "Which languages do your modules use?"
  info "Python, Git and the C compiler are always installed."
  ask_yes_no "Install Java (Temurin JDK $JAVA_VERSION)?" && WANT_JAVA=1
  ask_yes_no "Install Haskell (GHCup, GHC, Cabal)?" && WANT_HASKELL=1
fi
if [ -z "$ASKED_GHD" ] && [ ! -d "$GHD_APP" ]; then
  ask_yes_no "Install GitHub Desktop (optional graphical Git app)?" && WANT_GHD=1
fi

if ! id -Gn | tr ' ' '\n' | grep -qx admin; then
  warn "Your account is not an administrator. Homebrew and Java need an admin account."
fi
if [ -z "$DRY_RUN" ]; then
  step "Checking your password for sudo"
  info "Type your Mac login password. Nothing is shown while you type."
  sudo -v || warn "sudo failed; steps that need an administrator will fail."
fi

# ---------- Apple command line tools ----------
step "Apple command line tools (C compiler, Git)"
if xcode-select -p >/dev/null 2>&1; then
  info "Already installed at $(xcode-select -p)"
else
  run xcode-select --install
  if [ -z "$DRY_RUN" ]; then
    info "A window has opened. Click Install, accept the licence and wait for it to finish (10+ minutes)."
    read -r -p "    Press Enter here once the installer says it is done... " _ </dev/tty || true
    if xcode-select -p >/dev/null 2>&1; then
      info "Command line tools installed."
    else
      fail "The command line tools are still missing. Run this script again after installing them."
      exit 1
    fi
  fi
fi

# ---------- Homebrew ----------
step "Homebrew"
USE_BREW=""
[ -x "$BREW_PREFIX/bin/brew" ] && eval "$("$BREW_PREFIX/bin/brew" shellenv)"
if have brew; then
  info "Already installed: $(brew --version | head -n1)"
  USE_BREW=1
elif [ "$MACOS_MAJOR" -ge 15 ]; then
  [ -z "$DRY_RUN" ] && sudo -v
  if run_sh 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'; then
    [ -x "$BREW_PREFIX/bin/brew" ] && eval "$("$BREW_PREFIX/bin/brew" shellenv)"
    USE_BREW=1
  else
    fail "Homebrew install failed. Falling back to direct installers."
  fi
else
  warn "Homebrew supports macOS 15 Sequoia and newer; you have $MACOS_VERSION."
  warn "Using direct installers instead of forcing Homebrew."
fi
[ -n "$USE_BREW" ] && append_once "$HOME/.zprofile" "eval \"\$($BREW_PREFIX/bin/brew shellenv)\""

# ---------- Git, VS Code, Python ----------
step "Git, Visual Studio Code and Python"
if [ -n "$USE_BREW" ]; then
  brew_formula git || fail "brew could not install git."
  brew_formula python || fail "brew could not install python."
else
  info "Git comes with the Apple command line tools."
  if ! pkgutil --pkgs 2>/dev/null | grep -q '^org.python.Python.PythonFramework'; then
    run open "https://www.python.org/downloads/macos/"
    if [ -z "$DRY_RUN" ]; then
      info "A python.org page has opened. Download and run the macOS installer for the latest Python 3."
      read -r -p "    Press Enter once the Python installer has finished... " _ </dev/tty || true
    fi
  fi
fi

if [ -d "$VSCODE_APP" ]; then
  info "VS Code is already in Applications."
elif [ -n "$USE_BREW" ]; then
  run brew install --cask visual-studio-code || fail "brew could not install VS Code."
else
  install_app_zip "https://code.visualstudio.com/sha/download?build=stable&os=darwin-universal" "$VSCODE_APP" "VS Code"
fi

# Make the `code` command available (brew links it; the direct install does not).
VSCODE_BIN="$VSCODE_APP/Contents/Resources/app/bin"
if ! have code && [ -d "$VSCODE_BIN" ]; then
  append_once "$HOME/.zprofile" "export PATH=\"\$PATH:$VSCODE_BIN\""
  export PATH="$PATH:$VSCODE_BIN"
fi

# ---------- Java ----------
if [ -n "$WANT_JAVA" ]; then
  step "Java (Eclipse Temurin JDK $JAVA_VERSION)"
  if /usr/libexec/java_home -v "$JAVA_VERSION" >/dev/null 2>&1; then
    info "A JDK $JAVA_VERSION is already installed."
  elif [ -n "$USE_BREW" ]; then
    run brew install --cask "temurin@$JAVA_VERSION" || fail "brew could not install temurin@$JAVA_VERSION."
  else
    pkg="$(mktemp -d)/temurin.pkg"
    if run curl -fL --progress-bar -o "$pkg" \
         "https://api.adoptium.net/v3/installer/latest/$JAVA_VERSION/ga/mac/$ARCH/jdk/hotspot/normal/eclipse?project=jdk" \
       && run sudo installer -pkg "$pkg" -target /; then
      done_msg "Temurin JDK $JAVA_VERSION installed."
    else
      fail "Java install failed. Use adoptium.net/installation instead."
    fi
  fi
  JAVA_HOME="$(/usr/libexec/java_home -v "$JAVA_VERSION" 2>/dev/null)" && export JAVA_HOME
fi

# ---------- Haskell ----------
if [ -n "$WANT_HASKELL" ]; then
  step "Haskell (GHCup)"
  if have ghcup || [ -x "$HOME/.ghcup/bin/ghcup" ]; then
    info "GHCup is already installed; not reinstalling."
  else
    info "This downloads GHC, Cabal and HLS and can take 10+ minutes."
    run_sh "curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_INSTALL_HLS=1 BOOTSTRAP_HASKELL_ADJUST_BASHRC=1 sh" \
      || fail "GHCup installation failed. Read the installer output above."
  fi
  # shellcheck disable=SC1091
  [ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env"
fi

# ---------- GitHub Desktop ----------
if [ -n "$WANT_GHD" ]; then
  step "GitHub Desktop"
  if [ -d "$GHD_APP" ]; then
    info "Already in Applications."
  elif [ "$MACOS_MAJOR" -lt 12 ]; then
    warn "GitHub Desktop needs macOS 12 or newer; skipping."
  elif [ -n "$USE_BREW" ]; then
    run brew install --cask github || fail "brew could not install GitHub Desktop."
  else
    install_app_zip "https://central.github.com/deployments/desktop/desktop/latest/$GHD_ARCH" "$GHD_APP" "GitHub Desktop"
  fi
fi

# ---------- VS Code extensions ----------
if have code; then
  step "VS Code extensions"
  exts=(ms-python.python ms-vscode.cpptools)
  [ -n "$WANT_JAVA" ] && exts+=(vscjava.vscode-java-pack)
  [ -n "$WANT_HASKELL" ] && exts+=(haskell.haskell)
  installed_exts="$(code --list-extensions 2>/dev/null)"
  for e in "${exts[@]}"; do
    if printf '%s\n' "$installed_exts" | grep -qix "$e"; then
      info "$e (already installed)"
    else
      run code --install-extension "$e" >/dev/null 2>&1 || warn "Could not install extension $e (install it from the Extensions view)."
    fi
  done
fi

# ---------- Git identity ----------
if [ -z "$SKIP_GIT_CONFIG" ] && have git && git --version >/dev/null 2>&1; then
  step "Git name and email"
  if [ -n "$(git config --global user.name)" ] && [ -n "$(git config --global user.email)" ]; then
    info "Already set: $(git config --global user.name) <$(git config --global user.email)> (not changed)"
  elif [ -n "$DRY_RUN" ]; then
    info "Would ask for your name and email here."
  else
    info "Use your own name and the email on your GitHub account (or GitHub's noreply address)."
    git_name=""; git_email=""
    read -r -p "    Your name (Enter to skip): " git_name </dev/tty || git_name=""
    if [ -n "$git_name" ]; then
      read -r -p "    Your email: " git_email </dev/tty || git_email=""
      [ -z "$(git config --global user.name)" ] && run git config --global user.name "$git_name"
      [ -n "$git_email" ] && [ -z "$(git config --global user.email)" ] && run git config --global user.email "$git_email"
    fi
  fi
  [ -z "$(git config --global init.defaultBranch)" ] && run git config --global init.defaultBranch main
fi

# ---------- tests ----------
step "Testing each language with Hello, UCL!"
if [ -z "$TEST_DIR" ] || ! mkdir -p "$TEST_DIR" || ! cd "$TEST_DIR"; then
  fail "Could not create $TEST_DIR; skipping tests."
  exit 1
fi
info "Test files are in $TEST_DIR"

check() {  # name, expected-output, command...
  local name="$1" expected="$2" out
  shift 2
  if [ "$1" != bash ] && ! have "$1"; then
    record FAIL "$name" "$1 not found"
    return
  fi
  if out="$("$@" 2>&1)" && [[ "$out" == *"$expected"* ]]; then
    record PASS "$name" "$(printf '%s' "$out" | head -n1)"
  else
    record FAIL "$name" "$(printf '%s' "$out" | tail -n2 | tr '\n' ' ')"
  fi
}

check "Developer tools" "" cc --version
[ -n "$USE_BREW" ] && check "Homebrew" "Homebrew" brew --version
check "Git" "git version" git --version
check "VS Code" "." code --version

echo 'print("Hello, UCL!")' > "$TEST_DIR/hello.py"
rm -rf "$TEST_DIR/.venv"
check "Python version" "Python 3" python3 --version
check "Python venv" "" python3 -m venv "$TEST_DIR/.venv"
check "Python" "Hello, UCL!" "$TEST_DIR/.venv/bin/python" "$TEST_DIR/hello.py"

printf '#include <stdio.h>\nint main(void) { puts("Hello, UCL!"); return 0; }\n' > "$TEST_DIR/hello.c"
check "C (clang)" "Hello, UCL!" bash -c 'cc hello.c -o hello && ./hello'

if [ -n "$WANT_JAVA" ]; then
  cat > "$TEST_DIR/Hello.java" <<'EOF'
public class Hello {
    public static void main(String[] args) {
        System.out.println("Hello, UCL!");
    }
}
EOF
  check "Java" "Hello, UCL!" bash -c 'javac Hello.java && java Hello'
fi

if [ -n "$WANT_HASKELL" ]; then
  echo 'main = putStrLn "Hello, UCL!"' > "$TEST_DIR/hello.hs"
  check "Haskell" "Hello, UCL!" runghc hello.hs
  check "Cabal" "cabal" cabal --version
fi

if [ -n "$WANT_GHD" ]; then
  if [ -d "$GHD_APP" ]; then record PASS "GitHub Desktop" "$GHD_APP"; else record FAIL "GitHub Desktop" "not in Applications"; fi
fi

# ---------- summary ----------
step "Summary"
failed=0
for r in "${RESULTS[@]}"; do
  IFS='|' read -r status name detail <<<"$r"
  case "$status" in
    PASS) printf '    %s[ OK ]%s %-16s %s\n' "$GREEN" "$RESET" "$name" "$detail" ;;
    *)    printf '    %s[FAIL]%s %-16s %s\n' "$RED" "$RESET" "$name" "$detail"; failed=1 ;;
  esac
done

echo
if [ -n "$DRY_RUN" ]; then
  printf '%s\n' "${BOLD}Dry run finished.${RESET} Nothing was installed. The checks above show what is already on this Mac."
  exit 0
elif [ "$failed" -eq 0 ]; then
  printf '%s\n' "${GREEN}${BOLD}All checks passed.${RESET} Quit Terminal (Cmd+Q) and reopen it so PATH changes take effect."
else
  printf '%s\n' "${RED}${BOLD}Some checks failed.${RESET} Show $LOG to a tutor."
fi
exit "$failed"
