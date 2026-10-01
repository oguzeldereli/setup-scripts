<#
UCL Programming Tutor Scheme 2026-27 - environment setup for Windows 10/11

Easiest: double-click setup-windows.cmd (it runs this file with the right permissions).
Or, in a normal (NOT administrator) PowerShell window:
    powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -C -Java -Haskell
    powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -DryRun -All

Options:
    -C                 install WSL + Ubuntu with GCC for C coursework
    -Java              install Eclipse Temurin JDK (version from -JavaVersion, default 21)
    -Haskell           install GHCup, GHC, Cabal and HLS
    -All               all of the above
    -GitHubDesktop     also install GitHub Desktop (otherwise you are asked)
    -NoGitHubDesktop   do not install or ask about GitHub Desktop
    -JavaVersion N     JDK major version
    -SkipGitConfig     do not ask for your Git name and email
    -DryRun            print what would be installed without installing or changing anything,
                       then run the tests (they only write inside %USERPROFILE%\ucl-code\setup-test)

Python, Git and VS Code are always installed. With no language switches you are asked.

What this script will and will not do:
  * it only INSTALLS software; anything already installed is skipped, never upgraded or removed
  * it never changes existing Git settings; it only fills in ones that are empty
  * it only deletes files inside %USERPROFILE%\ucl-code\setup-test, a folder it creates for its own tests
  * downloads come only from WinGet / Microsoft Store, Microsoft (WSL, VS Code), python.org,
    Adoptium (Java), haskell.org (GHCup) and GitHub (Git, GitHub Desktop)
Everything printed is also appended to %USERPROFILE%\ucl-setup-log.txt. If something fails, show that file to a tutor.
#>
param(
    [switch]$C,
    [switch]$Java,
    [switch]$Haskell,
    [switch]$All,
    [switch]$GitHubDesktop,
    [switch]$NoGitHubDesktop,
    [ValidateRange(8, 99)][int]$JavaVersion = 21,
    [switch]$SkipGitConfig,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Log = Join-Path $env:USERPROFILE 'ucl-setup-log.txt'
$TestDir = Join-Path $env:USERPROFILE 'ucl-code\setup-test'
$Results = New-Object System.Collections.ArrayList

# winget exit codes that mean "already installed / nothing to do"
$WingetAlreadyInstalled = @(-1978335189, -1978335135)

# ---------- output helpers ----------
function Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "    $msg" }
function Warn($msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "    x $msg" -ForegroundColor Red }
function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Show-Cmd($text) { Write-Host "    `$ $text" -ForegroundColor DarkGray }

function Ask-YesNo($question) {
    $reply = Read-Host "    $question [y/N]"
    return ($reply -match '^[Yy]')
}

# Pick up PATH changes made by installers without reopening the window.
# Keeps any entries this session already added (e.g. a JDK found on disk).
function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($env:Path -split ';') + @($machine -split ';') + @($user -split ';') |
        Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Add-SessionPath($dir) {
    if ((Test-Path $dir) -and (($env:Path -split ';') -notcontains $dir)) { $env:Path = "$dir;$env:Path" }
}

# Installs one WinGet package. Never upgrades: callers only call this when the tool is missing.
function Winget-Install($id, $name, $source) {
    $wingetArgs = @('install', '-e', '--id', $id, '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($source) { $wingetArgs += @('--source', $source) }
    Show-Cmd ("winget " + ($wingetArgs -join ' '))
    if ($DryRun) { return $true }
    & winget @wingetArgs
    $code = $LASTEXITCODE
    if ($code -eq 0 -or $WingetAlreadyInstalled -contains $code) {
        Refresh-Path
        return $true
    }
    Fail "winget could not install $name (exit code $code)."
    return $false
}

function Record($status, $name, $detail) { [void]$Results.Add([pscustomobject]@{ Status = $status; Name = $name; Detail = $detail }) }

# Runs a command, records PASS if it succeeds and its output contains $expected.
function Check($name, $expected, [scriptblock]$block) {
    $global:LASTEXITCODE = 0
    try {
        $out = (& $block 2>&1 | Out-String).Trim()
    } catch [System.Management.Automation.CommandNotFoundException] {
        $out = "not found: $($_.TargetObject)"; $global:LASTEXITCODE = 1
    } catch {
        $out = "$_"; $global:LASTEXITCODE = 1
    }
    $ok = ($LASTEXITCODE -eq 0) -and $out.Contains($expected)
    $last = ($out -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 1)
    if ($ok) { Record 'PASS' $name $last } else { Record 'FAIL' $name $last }
}

# ---------- preflight ----------
$isAdmin = $false
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
if ($isAdmin) {
    Write-Host 'Please run this script from a normal (non-administrator) PowerShell window.' -ForegroundColor Yellow
    Write-Host 'It will ask for administrator permission only for the steps that need it.' -ForegroundColor Yellow
    exit 1
}

try { Start-Transcript -Path $Log -Append | Out-Null } catch { Warn "Could not write the log file $Log" }

Write-Host 'UCL Programming Tutor Scheme - Windows setup' -ForegroundColor White
$osName = 'Windows'
try { $os = Get-CimInstance Win32_OperatingSystem; $osName = "$($os.Caption) build $($os.BuildNumber)" } catch { }
Info "System: $osName ($env:PROCESSOR_ARCHITECTURE)"
Info "PowerShell: $($PSVersionTable.PSVersion)"
Info "Log file: $Log"
if ($DryRun) { Warn 'DRY RUN: commands are printed but nothing is installed or changed.' }

if ($All) { $C = $true; $Java = $true; $Haskell = $true }
if (-not ($C -or $Java -or $Haskell)) {
    Step 'Which languages do your modules use?'
    Info 'Python, Git and VS Code are always installed.'
    $C = Ask-YesNo 'Install C (WSL + Ubuntu + GCC)?'
    $Java = Ask-YesNo "Install Java (Temurin JDK $JavaVersion)?"
    $Haskell = Ask-YesNo 'Install Haskell (GHCup, GHC, Cabal)?'
}
if ($NoGitHubDesktop) { $GitHubDesktop = $false }
elseif (-not $GitHubDesktop) {
    $ghdInstalled = (Test-Path "$env:LOCALAPPDATA\GitHubDesktop\GitHubDesktop.exe")
    if (-not $ghdInstalled) { $GitHubDesktop = Ask-YesNo 'Install GitHub Desktop (optional graphical Git app)?' }
}

# ---------- WinGet ----------
Step 'Checking WinGet'
if (-not (Have 'winget')) {
    Fail 'winget was not found. Open Microsoft Store, update "App Installer", then run this script again.'
    if (-not $DryRun) { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' }
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
Info "winget $(winget --version)"

# ---------- Git and VS Code ----------
Step 'Git and Visual Studio Code'
if (Have 'git') { Info "Git already installed: $(git --version)" } else { [void](Winget-Install 'Git.Git' 'Git') }
if (Have 'code') { Info 'VS Code already installed.' } else { [void](Winget-Install 'Microsoft.VisualStudioCode' 'Visual Studio Code') }

# ---------- Python ----------
Step 'Python (Python Install Manager)'
$pyBin = Join-Path $env:LOCALAPPDATA 'Python\bin'
Add-SessionPath $pyBin
if (Have 'pymanager') {
    Info 'Python Install Manager already installed.'
} elseif (-not (Winget-Install 'Python.PythonInstallManager' 'Python Install Manager')) {
    Warn 'Trying the Microsoft Store package instead.'
    [void](Winget-Install '9NQ7512CXL7T' 'Python Install Manager (Store)' 'msstore')
}
Add-SessionPath $pyBin
if (Have 'py') {
    $env:PYTHON_MANAGER_CONFIRM = 'false'
    Show-Cmd 'py install default -y'
    if (-not $DryRun) { py install default -y }
    Refresh-Path
    Add-SessionPath $pyBin
} elseif (-not $DryRun) {
    Fail 'The py command is not available. Close this window, open a new one and run the script again.'
}

# ---------- Java ----------
function Find-Jdk($root) {
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "jdk-$JavaVersion*" } | Select-Object -First 1
}
if ($Java) {
    Step "Java (Eclipse Temurin JDK $JavaVersion)"
    $jdkRoot = 'C:\Program Files\Eclipse Adoptium'
    $jdk = Find-Jdk $jdkRoot
    if ($jdk) {
        Info "Temurin JDK $JavaVersion already installed at $($jdk.FullName)"
    } else {
        [void](Winget-Install "EclipseAdoptium.Temurin.$JavaVersion.JDK" "Temurin JDK $JavaVersion")
        $jdk = Find-Jdk $jdkRoot
    }
    if ($jdk) { Add-SessionPath (Join-Path $jdk.FullName 'bin') }
}

# ---------- Haskell ----------
if ($Haskell) {
    Step 'Haskell (GHCup)'
    if ((Have 'ghcup') -or (Test-Path 'C:\ghcup\bin\ghcup.exe')) {
        Info 'GHCup is already installed; not reinstalling.'
    } else {
        Info 'This downloads MSYS2, GHC, Cabal and HLS (about 5 GB) and can take 15+ minutes. Do not close this window.'
        Show-Cmd 'bootstrap-haskell.ps1 -InstallHLS -DisableCurl   (from https://www.haskell.org/ghcup/sh/)'
        if (-not $DryRun) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
                $bootstrap = Invoke-WebRequest 'https://www.haskell.org/ghcup/sh/bootstrap-haskell.ps1' -UseBasicParsing
                & ([ScriptBlock]::Create($bootstrap.Content)) -InstallHLS -DisableCurl
            } catch {
                Fail "GHCup installation failed: $_"
            }
            Refresh-Path
        }
    }
    Add-SessionPath 'C:\ghcup\bin'
}

# ---------- WSL for C ----------
$wslDistro = $null
if ($C) {
    Step 'WSL + Ubuntu for C'
    if (Have 'wsl.exe') {
        # wsl.exe prints UTF-16; strip NULs so the names can be matched.
        $wslList = ((wsl.exe -l -q 2>$null | Out-String) -replace "`0", '') -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $wslDistro = $wslList | Where-Object { $_ -like 'Ubuntu*' } | Select-Object -First 1
    }
    if ($wslDistro) {
        Info "Found WSL distribution '$wslDistro'. Installing GCC, Make, Git and Python inside it (install only, no upgrades)..."
        $aptCmd = 'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y --no-remove build-essential git python3 python3-venv python3-pip'
        Show-Cmd "wsl -d $wslDistro -u root -- bash -c `"$aptCmd`""
        if (-not $DryRun) {
            wsl.exe -d $wslDistro -u root -- bash -c $aptCmd
            if ($LASTEXITCODE -ne 0) { Fail "apt inside $wslDistro failed. Open Ubuntu and run: sudo apt update" }
        }
    } else {
        Info 'Ubuntu is not installed in WSL yet. This needs administrator permission: click Yes in the window that appears.'
        Show-Cmd 'wsl --install -d Ubuntu   (as administrator)'
        if (-not $DryRun) {
            try {
                $p = Start-Process wsl.exe -ArgumentList '--install', '-d', 'Ubuntu' -Verb RunAs -Wait -PassThru
                Info "wsl --install finished with exit code $($p.ExitCode)."
            } catch {
                Fail 'Administrator permission was refused, so WSL was not installed.'
            }
        }
        Warn 'Next: RESTART your computer, open "Ubuntu" from the Start menu and create your Linux username and password.'
        Warn 'Then run this script again (double-click setup-windows.cmd) and answer y to C to finish installing GCC.'
        Record 'TODO' 'WSL / Ubuntu' 'restart, open Ubuntu once, then run this script again and choose C'
    }
}

# ---------- GitHub Desktop ----------
if ($GitHubDesktop) {
    Step 'GitHub Desktop'
    if (Test-Path "$env:LOCALAPPDATA\GitHubDesktop\GitHubDesktop.exe") {
        Info 'Already installed.'
    } else {
        [void](Winget-Install 'GitHub.GitHubDesktop' 'GitHub Desktop')
    }
}

# ---------- VS Code extensions ----------
if (Have 'code') {
    Step 'VS Code extensions'
    $exts = @('ms-python.python')
    if ($C) { $exts += 'ms-vscode-remote.remote-wsl'; $exts += 'ms-vscode.cpptools' }
    if ($Java) { $exts += 'vscjava.vscode-java-pack' }
    if ($Haskell) { $exts += 'haskell.haskell' }
    $installedExts = @(code --list-extensions 2>$null)
    foreach ($e in $exts) {
        if ($installedExts -contains $e) { Info "$e (already installed)"; continue }
        Show-Cmd "code --install-extension $e"
        if ($DryRun) { continue }
        code --install-extension $e *> $null
        if ($LASTEXITCODE -ne 0) { Warn "Could not install extension $e (install it from the Extensions view)." }
    }
}

# ---------- Git identity ----------
if (-not $SkipGitConfig -and (Have 'git')) {
    Step 'Git name and email'
    $gitName = git config --global user.name
    $gitEmail = git config --global user.email
    if ($gitName -and $gitEmail) {
        Info "Already set: $gitName <$gitEmail> (not changed)"
    } elseif ($DryRun) {
        Info 'Would ask for your name and email here.'
    } else {
        Info "Use your own name and the email on your GitHub account (or GitHub's noreply address)."
        $newName = Read-Host '    Your name (Enter to skip)'
        if ($newName) {
            $newEmail = Read-Host '    Your email'
            if (-not $gitName) { git config --global user.name "$newName" }
            if ($newEmail -and -not $gitEmail) { git config --global user.email "$newEmail" }
        }
    }
    if (-not (git config --global init.defaultBranch)) {
        Show-Cmd 'git config --global init.defaultBranch main'
        if (-not $DryRun) { git config --global init.defaultBranch main }
    }
}

# ---------- tests ----------
Step 'Testing each language with Hello, UCL!'
try {
    New-Item -ItemType Directory -Force -Path $TestDir -ErrorAction Stop | Out-Null
    Set-Location -LiteralPath $TestDir -ErrorAction Stop
} catch {
    Fail "Could not create $TestDir; skipping tests."
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
Info "Test files are in $TestDir"

Check 'Git' 'git version' { git --version }
Check 'VS Code' '.' { code --version }

Set-Content -LiteralPath (Join-Path $TestDir 'hello.py') -Value 'print("Hello, UCL!")' -Encoding ASCII
$venv = Join-Path $TestDir '.venv'
if (Test-Path -LiteralPath $venv) { Remove-Item -LiteralPath $venv -Recurse -Force }
Check 'Python' 'Python 3' { python --version }
Check 'Python venv' '' { python -m venv $venv }
Check 'Python run' 'Hello, UCL!' { & (Join-Path $venv 'Scripts\python.exe') (Join-Path $TestDir 'hello.py') }

if ($C -and $wslDistro) {
    Set-Content -LiteralPath (Join-Path $TestDir 'hello.c') -Value "#include <stdio.h>`nint main(void) { puts(`"Hello, UCL!`"); return 0; }" -Encoding ASCII
    # WSL starts in the current Windows folder (/mnt/c/Users/.../setup-test); the binary goes to Linux /tmp.
    Check 'C (gcc in WSL)' 'Hello, UCL!' { wsl.exe -d $wslDistro -- bash -c 'gcc hello.c -o /tmp/ucl-hello && /tmp/ucl-hello' }
}

if ($Java) {
    Set-Content -LiteralPath (Join-Path $TestDir 'Hello.java') -Encoding ASCII -Value @'
public class Hello {
    public static void main(String[] args) {
        System.out.println("Hello, UCL!");
    }
}
'@
    Check 'Java' 'Hello, UCL!' { javac Hello.java; if ($LASTEXITCODE -eq 0) { java Hello } }
}

if ($Haskell) {
    Set-Content -LiteralPath (Join-Path $TestDir 'hello.hs') -Value 'main = putStrLn "Hello, UCL!"' -Encoding ASCII
    Check 'Haskell' 'Hello, UCL!' { runghc hello.hs }
    Check 'Cabal' 'cabal' { cabal --version }
}

if ($GitHubDesktop) {
    if (Test-Path "$env:LOCALAPPDATA\GitHubDesktop\GitHubDesktop.exe") { Record 'PASS' 'GitHub Desktop' 'installed' }
    else { Record 'FAIL' 'GitHub Desktop' 'not found' }
}

# ---------- summary ----------
Step 'Summary'
$failed = $false
foreach ($r in $Results) {
    switch ($r.Status) {
        'PASS' { Write-Host '    [ OK ] ' -ForegroundColor Green -NoNewline }
        'TODO' { Write-Host '    [TODO] ' -ForegroundColor Yellow -NoNewline }
        default { Write-Host '    [FAIL] ' -ForegroundColor Red -NoNewline; $failed = $true }
    }
    Write-Host ('{0,-16} {1}' -f $r.Name, $r.Detail)
}

Write-Host ''
if ($DryRun) {
    Write-Host 'Dry run finished. Nothing was installed. The checks above show what is already on this computer.'
} elseif ($failed) {
    Write-Host "Some checks failed. Close this window and run the script again (installers sometimes need a fresh window)." -ForegroundColor Red
    Write-Host "If it still fails, show $Log to a tutor." -ForegroundColor Red
} else {
    Write-Host 'Setup finished. Close this window; terminals you open from now on will find the new tools.' -ForegroundColor Green
}
try { Stop-Transcript | Out-Null } catch { }
if ($failed -and -not $DryRun) { exit 1 } else { exit 0 }
