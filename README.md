# UCL Programming Tutor Scheme 2026–27: setup scripts

These scripts automate the steps in `UCL_Programming_Environment_Setup_2026-27.pptx`. Each one installs the tools, runs a "Hello, UCL!" program in every language you chose, and ends with a pass/fail summary.

| Your laptop | Run this |
|---|---|
| Windows 10 / 11 | `setup-windows.cmd` (double-click) |
| macOS | `bash setup-macos.sh` |
| Linux: Ubuntu, Debian, Mint, Fedora, RHEL-likes, openSUSE, Arch, or Ubuntu inside WSL | `bash setup-linux.sh` |

Every run is appended to `ucl-setup-log.txt` in your home folder. **If anything fails, show that file to a tutor.** Don't reinstall things at random.

## Safe by design

- **Install only.** Anything already installed is skipped. Nothing is upgraded or removed:
  - `apt` runs with `--no-remove`.
  - `pacman` and `zypper` stop instead of resolving conflicts.
  - Homebrew is told not to upgrade existing packages.
- **Your settings are left alone.** Git name, email and default branch are set only if they're empty. Shell profiles only get lines appended, and only if those lines aren't already there.
- **Deletes only its own files.** The scripts delete files only inside `~/ucl-code/setup-test`, a folder they create for the tests.
- **Official sources only.** Your OS package manager or WinGet, Apple, Homebrew, Microsoft, python.org, Adoptium, haskell.org and GitHub.
- **Normal user, not admin.** Run the scripts as yourself, not as root or administrator. They ask for your password or admin permission only for steps that need it.
- **`--dry-run` / `-DryRun`.** Prints every command it *would* run, installs nothing, then shows which tools already work.
- **Safe to re-run.** Running again is how you resume after a failure or a restart.

## What gets installed

| | Windows | macOS | Linux |
|---|---|---|---|
| Always | Git, VS Code, Python (Install Manager) | Apple command line tools, Homebrew\*, Git, VS Code, Python | GCC + Make, Git, Python + venv, VS Code\*\* |
| C | WSL + Ubuntu + GCC (choose it) | always (Apple clang) | always (GCC) |
| Java | Eclipse Temurin JDK 21 | Eclipse Temurin JDK 21 | OpenJDK 21 from your distro |
| Haskell | GHCup (GHC, Cabal, HLS) | GHCup | GHCup |
| GitHub Desktop (optional, asked) | yes | yes (macOS 12+) | no official Linux build |

\* Only on macOS 15 Sequoia or newer. On older versions the script uses direct installers instead.

\*\* VS Code comes from Microsoft's repository on apt, dnf and zypper systems. It's skipped inside WSL: use VS Code on Windows with the WSL extension. On Arch, the script tells you how to install it from the AUR.

The scripts also install the matching VS Code extensions. They ask for your Git name and email if those aren't set yet.

## How to run

If you don't pass any language options, the script asks which languages you need. Only install the ones your modules use.

### Windows

1. Download this folder and unzip it.
2. Double-click **`setup-windows.cmd`**. Don't use "Run as administrator"; the script asks for permission when it needs it.
3. If you chose C and WSL wasn't installed yet, **restart** your computer. Then open **Ubuntu** from the Start menu, create a Linux username and password, and run `setup-windows.cmd -C` again.

PowerShell alternative:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -C -Java -Haskell
```

### macOS

Open **Terminal** (Applications › Utilities) in the folder containing the script:

```bash
bash setup-macos.sh
```

You'll be asked for your Mac password (nothing appears as you type). If a window asks to install the command line developer tools, click **Install**.

### Linux

```bash
bash setup-linux.sh
```

Run it as your normal user, not with `sudo`. On immutable systems (Fedora Silverblue, Bazzite and similar), run it inside a `toolbox` or `distrobox` container.

## Options

| bash (macOS / Linux) | PowerShell (Windows) | Meaning |
|---|---|---|
| `--c` | `-C` | C toolchain (on Windows this means WSL; elsewhere it's always installed) |
| `--java` | `-Java` | Java JDK |
| `--haskell` | `-Haskell` | GHCup, GHC, Cabal, HLS |
| `--all` | `-All` | All of the above |
| `--github-desktop` / `--no-github-desktop` | `-GitHubDesktop` / `-NoGitHubDesktop` | Install GitHub Desktop, or don't ask about it (Windows and macOS) |
| `--java-version 25` | `-JavaVersion 25` | Use a different JDK version if your module asks for one (default 21) |
| `--skip-git-config` | `-SkipGitConfig` | Don't ask for your Git name and email |
| `--dry-run` | `-DryRun` | Show what would be installed; change nothing |

## After it finishes

- Close and reopen your terminal so the new `PATH` takes effect.
- The test programs are in `~/ucl-code/setup-test`. Your own work can go anywhere, for example `~/ucl-code/<module>`.
- Next steps from the slides: make your first Git commit (slide 36), and apply for the GitHub Student Pack and the JetBrains licence (slide 4).
