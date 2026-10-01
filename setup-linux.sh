#!/usr/bin/env bash
# UCL Programming Tutor Scheme 2026-27 - environment setup for Linux (and Ubuntu under WSL)
#
# Supported package managers:
#   apt     Ubuntu, Debian, Linux Mint, Pop!_OS, elementary, WSL Ubuntu ...
#   dnf     Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux ...
#   zypper  openSUSE Tumbleweed / Leap, SLE
#   pacman  Arch, Manjaro, EndeavourOS ...
#
# Usage:
#   bash setup-linux.sh                  # asks which languages you need
#   bash setup-linux.sh --all            # Python, C, Java and Haskell
#   bash setup-linux.sh --dry-run --all  # only show what would be installed; changes nothing
#
# Run "bash setup-linux.sh --help" for all options.
#
# What this script will and will not do:
#   * it only INSTALLS packages; it never upgrades your system or removes packages
#     (apt runs with --no-remove; pacman/zypper abort instead of resolving conflicts)
#   * it only ADDS lines to config files, and only if they are not already there
#   * it only deletes files inside ~/ucl-code/setup-test, a folder it creates for its own tests
#   * downloads come only from your distribution, Microsoft (VS Code) and haskell.org (GHCup)
# Everything printed is also appended to ~/ucl-setup-log.txt. If something fails, show that file to a tutor.

# The whole script is one { ... } block so bash reads all of it before running anything.
# That keeps "curl ... | bash" safe even if a command reads from standard input.
{
set -uo pipefail

JAVA_VERSION="${JAVA_VERSION:-21}"
WANT_JAVA=""; WANT_HASKELL=""; ASKED_LANGS=""
SKIP_GIT_CONFIG=""
DRY_RUN=""
LOG="$HOME/ucl-setup-log.txt"
TEST_DIR="$HOME/ucl-code/setup-test"

usage() {
  cat <<'EOF'
Usage: bash setup-linux.sh [options]

  --java              install a Java JDK
  --haskell           install GHCup, GHC, Cabal and HLS
  --all               install everything (Python, C, Java, Haskell)
  --c, --python       accepted for consistency; Python, C and Git are always installed
  --github-desktop    accepted for consistency; GitHub Desktop has no official Linux build
  --java-version N    JDK major version (default: 21)
  --skip-git-config   do not ask for your Git name and email
  --dry-run           print what would be installed without installing or changing anything;
                      then run the tests (they only write inside ~/ucl-code/setup-test)
  -h, --help          show this help

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
    --java-version)
      shift
      case "${1:-}" in
        ''|*[!0-9]*) echo "--java-version needs a number, e.g. --java-version 21"; exit 1 ;;
      esac
      JAVA_VERSION="$1" ;;
    --github-desktop|--no-github-desktop) ;;  # GitHub Desktop has no official Linux build
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
  bash -c "$1"
}

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

RESULTS=()
record() { RESULTS+=("$1|$2|$3"); }  # status|name|detail

# ---------- preflight ----------
if [ "$(uname -s)" != "Linux" ]; then
  echo "This script is for Linux. Use setup-macos.sh on a Mac or setup-windows.cmd on Windows."
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "Please run this script as your normal user, not as root or with sudo."
  echo "It will ask for your password when it needs it."
  exit 1
fi
if [ -e /run/ostree-booted ]; then
  echo "This looks like an immutable system (Fedora Silverblue/Kinoite, Bazzite, ...)."
  echo "Packages cannot be installed the normal way here. Run this script inside a toolbox or distrobox container."
  exit 1
fi

PM=""
for candidate in apt-get dnf zypper pacman; do
  if have "$candidate"; then PM="$candidate"; break; fi
done
if [ -z "$PM" ]; then
  echo "No supported package manager found (apt, dnf, zypper or pacman)."
  echo "Install Git, GCC/Make, Python 3 (with venv) and VS Code by hand, following the slides."
  exit 1
fi

{ echo; echo "===== setup-linux.sh $(date) ====="; } >>"$LOG"
exec > >(tee -a "$LOG") 2>&1

IS_WSL=""
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1
DISTRO="$( (. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-$ID}") || echo unknown)"

printf '%s\n' "${BOLD}UCL Programming Tutor Scheme - Linux setup${RESET}"
info "System: $DISTRO ($(uname -m))${IS_WSL:+ under WSL}"
info "Package manager: $PM"
info "Log file: $LOG"
[ -n "$DRY_RUN" ] && warn "DRY RUN: commands are printed but nothing is installed or changed."

if [ -z "$ASKED_LANGS" ]; then
  step "Which languages do your modules use?"
  info "Python, Git and the C compiler are always installed."
  ask_yes_no "Install Java (JDK $JAVA_VERSION)?" && WANT_JAVA=1
  ask_yes_no "Install Haskell (GHCup, GHC, Cabal)?" && WANT_HASKELL=1
fi

if [ -z "$DRY_RUN" ]; then
  step "Checking your password for sudo"
  info "Type your password. Nothing is shown while you type."
  if ! sudo -v; then
    fail "sudo failed. Your account must be allowed to install software (ask the owner of the computer)."
    exit 1
  fi
fi

# ---------- package manager wrappers (install only; never upgrade or remove) ----------
pkg_refresh() {
  case "$PM" in
    apt-get) run sudo apt-get update ;;
    zypper)  run sudo zypper --non-interactive refresh ;;
    *) return 0 ;;  # dnf refreshes by itself; pacman -Sy alone would risk a partial upgrade
  esac
}

pkg_install() {  # all-or-nothing install of the given packages
  case "$PM" in
    apt-get) run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove "$@" ;;
    dnf)     run sudo dnf install -y "$@" ;;
    zypper)  run sudo zypper --non-interactive install --no-recommends "$@" ;;
    pacman)  run sudo pacman -S --needed --noconfirm "$@" ;;
  esac
}

# Installs packages one at a time so that one unavailable name does not stop the rest.
pkg_install_each() {
  local p
  for p in "$@"; do
    pkg_install "$p" >/dev/null 2>&1 || warn "Package $p could not be installed (it may not exist on $DISTRO)."
  done
}

pkg_available() {
  case "$PM" in
    apt-get) apt-cache show "$1" >/dev/null 2>&1 ;;
    dnf)     dnf -q info "$1" >/dev/null 2>&1 ;;
    zypper)  zypper --non-interactive search -x "$1" >/dev/null 2>&1 ;;
    pacman)  pacman -Si "$1" >/dev/null 2>&1 ;;
  esac
}

pacman_hint() {
  [ "$PM" = pacman ] && warn "If pacman reported 404 errors, update your system first with: sudo pacman -Syu"
}

# ---------- base packages ----------
case "$PM" in
  apt-get) BASE_PKGS=(build-essential git python3 python3-venv python3-pip curl ca-certificates) ;;
  dnf)     BASE_PKGS=(gcc gcc-c++ make git python3 python3-pip curl) ;;
  zypper)  BASE_PKGS=(gcc gcc-c++ make git python3 python3-pip curl) ;;
  pacman)  BASE_PKGS=(base-devel git python python-pip curl) ;;
esac

step "Installing Git, the C toolchain and Python"
pkg_refresh || warn "Refreshing package lists failed; continuing with the existing lists."
if ! pkg_install "${BASE_PKGS[@]}"; then
  warn "Installing everything at once failed; trying each package separately."
  pacman_hint
  pkg_install_each "${BASE_PKGS[@]}"
fi

# ---------- VS Code ----------
step "Visual Studio Code"
VSCODE_REPO_LINE='[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n'

if [ -n "$IS_WSL" ]; then
  info "You are inside WSL: use VS Code installed on Windows with the WSL extension."
  info "Running 'code .' in this terminal opens the current folder in that VS Code."
elif have code; then
  info "Already installed."
else
  case "$PM" in
    apt-get)
      case "$(dpkg --print-architecture)" in
        amd64) vsc_arch=x64 ;; arm64) vsc_arch=arm64 ;; armhf) vsc_arch=armhf ;; *) vsc_arch="" ;;
      esac
      if [ -z "$vsc_arch" ]; then
        fail "There is no VS Code package for this processor."
      else
        deb="$(mktemp -d)/vscode.deb"
        # Answer the "add Microsoft's apt repository?" question in advance so it does not block.
        have debconf-set-selections && run_sh "echo 'code code/add-microsoft-repo boolean true' | sudo debconf-set-selections"
        if run curl -fL --progress-bar -o "$deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-$vsc_arch" \
           && run chmod 644 "$deb" \
           && pkg_install "$deb"; then
          [ -z "$DRY_RUN" ] && info "VS Code installed."
        else
          fail "VS Code install failed. Download the .deb from code.visualstudio.com/download instead."
        fi
      fi
      ;;
    dnf|zypper)
      repo_file=/etc/yum.repos.d/vscode.repo
      [ "$PM" = zypper ] && repo_file=/etc/zypp/repos.d/vscode.repo
      run sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      if [ -e "$repo_file" ]; then
        info "$repo_file already exists; leaving it unchanged."
      else
        run_sh "printf '$VSCODE_REPO_LINE' | sudo tee $repo_file >/dev/null"
      fi
      pkg_install code || fail "VS Code install failed. See code.visualstudio.com/docs/setup/linux"
      ;;
    pacman)
      warn "VS Code is not in the official Arch repositories."
      warn "Install it from the AUR (package visual-studio-code-bin) with your AUR helper, e.g.: yay -S visual-studio-code-bin"
      warn "or install 'code' (open-source build) with: sudo pacman -S code"
      ;;
  esac
fi

# ---------- Java ----------
if [ -n "$WANT_JAVA" ]; then
  step "Java (JDK $JAVA_VERSION)"
  case "$PM" in
    apt-get) java_pkg="openjdk-$JAVA_VERSION-jdk"; java_fallback=default-jdk ;;
    dnf)     java_pkg="java-$JAVA_VERSION-openjdk-devel"; java_fallback=java-latest-openjdk-devel ;;
    zypper)  java_pkg="java-$JAVA_VERSION-openjdk-devel"; java_fallback="" ;;
    pacman)  java_pkg="jdk$JAVA_VERSION-openjdk"; java_fallback=jdk-openjdk ;;
  esac
  if pkg_available "$java_pkg"; then
    pkg_install "$java_pkg" || { fail "Could not install $java_pkg."; pacman_hint; }
  elif [ -n "$java_fallback" ] && pkg_available "$java_fallback"; then
    warn "$java_pkg is not available on $DISTRO; installing $java_fallback (a different JDK version)."
    warn "If your module needs exactly JDK $JAVA_VERSION, use adoptium.net/installation."
    pkg_install "$java_fallback" || fail "Could not install $java_fallback."
  else
    fail "No JDK $JAVA_VERSION package found. Use adoptium.net/installation."
  fi
fi

# ---------- Haskell ----------
if [ -n "$WANT_HASKELL" ]; then
  step "Haskell (GHCup)"
  info "Installing libraries GHCup needs..."
  case "$PM" in
    apt-get) pkg_install_each build-essential curl libffi-dev libgmp-dev libncurses-dev zlib1g-dev pkg-config ;;
    dnf)     pkg_install_each gcc gcc-c++ make curl xz perl gmp gmp-devel ncurses ncurses-devel zlib-devel libffi-devel ;;
    zypper)  pkg_install_each gcc gcc-c++ make curl xz perl gmp-devel ncurses-devel zlib-devel libffi-devel ;;
    pacman)  pkg_install_each base-devel curl xz perl gmp ncurses zlib libffi ;;
  esac
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

# ---------- VS Code extensions ----------
if [ -z "$IS_WSL" ] && have code; then
  step "VS Code extensions"
  exts=(ms-python.python ms-vscode.cpptools)
  [ -n "$WANT_JAVA" ] && exts+=(vscjava.vscode-java-pack)
  [ -n "$WANT_HASKELL" ] && exts+=(haskell.haskell)
  for e in "${exts[@]}"; do
    if code --list-extensions 2>/dev/null | grep -qix "$e"; then
      info "$e (already installed)"
    else
      run code --install-extension "$e" >/dev/null 2>&1 || warn "Could not install extension $e (install it from the Extensions view)."
    fi
  done
fi

# ---------- GitHub Desktop ----------
step "GitHub Desktop"
info "GitHub does not publish GitHub Desktop for Linux. Use Git in the terminal or VS Code's Source Control view."

# ---------- Git identity ----------
if [ -z "$SKIP_GIT_CONFIG" ] && have git; then
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

check "Git" "git version" git --version
if [ -n "$IS_WSL" ]; then
  if have code; then record PASS "VS Code (WSL)" "code command found"; else record WARN "VS Code (WSL)" "install VS Code + the WSL extension on Windows"; fi
elif [ "$PM" = pacman ] && ! have code; then
  record WARN "VS Code" "install from AUR (see above)"
else
  check "VS Code" "." code --version
fi

echo 'print("Hello, UCL!")' > "$TEST_DIR/hello.py"
rm -rf "$TEST_DIR/.venv"
check "Python version" "Python 3" python3 --version
check "Python venv" "" python3 -m venv "$TEST_DIR/.venv"
check "Python" "Hello, UCL!" "$TEST_DIR/.venv/bin/python" "$TEST_DIR/hello.py"
if have python3 && ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then
  case "$PM" in
    zypper) py_hint="sudo zypper install python312, then use python3.12" ;;
    dnf)    py_hint="sudo dnf install python3.12, then use python3.12" ;;
    *)      py_hint="install a newer python3.x package" ;;
  esac
  record WARN "Python 3.9+" "python3 is older than 3.9: $py_hint"
fi

printf '#include <stdio.h>\nint main(void) { puts("Hello, UCL!"); return 0; }\n' > "$TEST_DIR/hello.c"
check "C (gcc)" "Hello, UCL!" bash -c 'gcc hello.c -o hello && ./hello'

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

# ---------- summary ----------
step "Summary"
failed=0
for r in "${RESULTS[@]}"; do
  IFS='|' read -r status name detail <<<"$r"
  case "$status" in
    PASS) printf '    %s[ OK ]%s %-15s %s\n' "$GREEN" "$RESET" "$name" "$detail" ;;
    WARN) printf '    %s[WARN]%s %-15s %s\n' "$YELLOW" "$RESET" "$name" "$detail" ;;
    *)    printf '    %s[FAIL]%s %-15s %s\n' "$RED" "$RESET" "$name" "$detail"; failed=1 ;;
  esac
done

echo
if [ -n "$DRY_RUN" ]; then
  printf '%s\n' "${BOLD}Dry run finished.${RESET} Nothing was installed. The checks above show what is already on this computer."
elif [ "$failed" -eq 0 ]; then
  printf '%s\n' "${GREEN}${BOLD}All checks passed.${RESET} Close and reopen your terminal so PATH changes take effect."
else
  printf '%s\n' "${RED}${BOLD}Some checks failed.${RESET} Show $LOG to a tutor."
fi
[ -n "$DRY_RUN" ] && exit 0
exit "$failed"
}
