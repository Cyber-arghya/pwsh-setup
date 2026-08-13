# ============================================================
#  dev-setup.ps1  —  Windows 11 Pro Dev Environment Setup
#  PowerShell equivalent of dev-setup.sh
#
#  Run in an elevated (Admin) PowerShell:
#    powershell -ExecutionPolicy Bypass -File .\dev-setup.ps1
#  or right-click -> Run with PowerShell.
# ============================================================
param(
    [switch]$SkipWinget,      # Skip installing winget packages
    [switch]$NoProfile        # Skip regenerating the PowerShell profile
)

$ErrorActionPreference = 'Stop'

# ------------------- Configuration ---------------------------
$USER_NAME  = "Cyber-arghya"
$USER_EMAIL = "work.arghya01@gmail.com"
$SSH_KEY_PATH = "$HOME\.ssh\id_ed25519"
$GITIGNORE_FILE = "$HOME\.gitignore_global"
$PROFILE_FILE   = $PROFILE

# ------------------- Colors ---------------------------------
function Write-SetupLog {
    param([string]$Msg, [string]$Color = "Green")
    Write-Host "[SETUP] $Msg" -ForegroundColor $Color
}

# ============================================================
#  Helper: Install a winget package if it isn't already present
# ============================================================
function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$CheckCmd,
        [string]$Name
    )
    if (Get-Command $CheckCmd -ErrorAction SilentlyContinue) {
        Write-SetupLog "$Name is already installed. Skipping."
        return $true
    }
    Write-SetupLog "Installing $Name via winget..." -Color Blue
    try {
        winget install --id $Id -e --source winget --accept-package-agreements --accept-source-agreements --silent
        Write-SetupLog "$Name installed successfully."
        return $true
    } catch {
        Write-SetupLog "ERROR: Failed to install $Name. Continuing..." -Color Red
        return $false
    }
}

# ============================================================
#  Git suite: install + global config + global gitignore
# ============================================================
function Install-GitSuite {
    Write-SetupLog "Checking Git installation..."
    $gitOk = Install-WingetPackage -Id "Git.Git" -CheckCmd "git" -Name "Git"
    if (-not $gitOk) { return }

    Write-SetupLog "Configuring Git for $USER_NAME <$USER_EMAIL>..."
    git config --global user.name "$USER_NAME"
    git config --global user.email "$USER_EMAIL"
    git config --global init.defaultBranch main

    # Aliases (mirror of .bash_aliases git aliases)
    git config --global alias.s "status"
    git config --global alias.a "add ."
    git config --global alias.cm "commit -m"
    git config --global alias.co "checkout"
    git config --global alias.br "branch"
    git config --global alias.last "log -1 HEAD"
    git config --global alias.unstage "restore --staged"
    git config --global alias.undo "reset --soft HEAD~1"
    git config --global alias.hist "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)' --all"
    git config --global alias.publish "!gh repo create --public --push --source=."
   git config --global alias.ignored '!git status --ignored -s | grep "!!"'
    git config --global alias.why "check-ignore -v"

    # Global Gitignore
    Write-SetupLog "Creating global .gitignore..."
    $gitignore = @'
# =========================
# OPERATING SYSTEMS
# =========================
# macOS
.DS_Store
.AppleDouble
.LSOverride
._*

# Windows
Thumbs.db
Desktop.ini
$RECYCLE.BIN/
*.lnk

# Linux
*~
.fuse_hidden*
.directory
.Trash-*

# =========================
# EDITORS & IDES
# =========================
.vscode/
.idea/
*.swp
*.swo
*.sublime-workspace
*.sublime-project
.settings/
.classpath
.project
*.iml

# =========================
# LOGS & DATABASES
# =========================
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
*.sqlite
*.sqlite3
*.db
dump.rdb

# =========================
# LANGUAGES
# =========================
# Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/
env/
.pytest_cache/

# Node.js
node_modules/
dist/
build/
.next/
.nuxt/
coverage/
.npm/

# C / C++
*.o
*.obj
*.exe
*.out
a.out
*.dll
*.so
*.dylib
bin/
obj/
x64/
x86/
cmake-build-*/
CMakeFiles/
CMakeCache.txt

# Java
*.class
*.jar
*.war
*.ear

# Rust
target/

# Go
bin/

# =========================
# MISC / SECURITY
# =========================
*.zip
*.tar
*.tar.gz
*.rar
*.7z

# Environment Variables (CRITICAL)
.env
.env.*
!.env.example
.python-version
'@
    Set-Content -Path $GITIGNORE_FILE -Value $gitignore -Encoding UTF8
    git config --global core.excludesfile "$GITIGNORE_FILE"
    Write-SetupLog "Global .gitignore saved to $GITIGNORE_FILE"
}

# ============================================================
#  Optional: SSH key
# ============================================================
function New-SshKey {
    Write-SetupLog "Setting up SSH key..."
    if (-not (Test-Path $SSH_KEY_PATH)) {
        ssh-keygen -t ed25519 -C "$USER_EMAIL" -f "$SSH_KEY_PATH" -N '""'
        Get-Content "$SSH_KEY_PATH.pub"
        Write-SetupLog "Add the above key to your GitHub account." -Color Blue
    } else {
        Write-SetupLog "SSH key already exists."
    }
}

# ============================================================
#  Optional: GitHub CLI + GHCR docker login
# ============================================================
function Install-GhCli {
    Write-SetupLog "Checking GitHub CLI..."
    $ghOk = Install-WingetPackage -Id "GitHub.cli" -CheckCmd "gh" -Name "GitHub CLI"
    if (-not $ghOk) { return }

    # Only login if not already authenticated
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-SetupLog "Not logged into GitHub. Starting login..." -Color Blue
        gh auth login --scopes "write:packages,read:packages"
    } else {
        Write-SetupLog "Already authenticated with GitHub CLI. Skipping login."
        gh auth status
    }

    # Safety check: only log into GHCR if Docker is present
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        Write-SetupLog "Authenticating Docker with GHCR..."
        $ghUser = gh api user -q ".login"
        $token  = gh auth token
        $token | docker login ghcr.io -u $ghUser --password-stdin
    } else {
        Write-SetupLog "Docker is not installed or running. Skipping GHCR login." -Color Blue
    }
}

# ============================================================
#  Optional: Rust via rustup (non-interactive)
# ============================================================
function Install-Rust {
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Write-SetupLog "Rust is already installed. Skipping."
        return
    }
    Write-SetupLog "Installing Rust (non-interactive)..."
    try {
        & curl.exe --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs -o $env:TEMP\rustup-init.exe
        & $env:TEMP\rustup-init.exe -y
        Write-SetupLog "Rust installed successfully."
    } catch {
        Write-SetupLog "ERROR: Failed to install Rust. Continuing..." -Color Red
    }
}

# ============================================================
#  Optional: Node.js LTS via winget (nvm alternative)
# ============================================================
function Install-Node {
    Install-WingetPackage -Id "OpenJS.NodeJS.LTS" -CheckCmd "node" -Name "Node.js LTS"
}

# ============================================================
#  PowerShell profile: aliases + custom functions
# ============================================================
function Set-Profile {
    if ($NoProfile) { Write-SetupLog "Profile regeneration skipped (NoProfile)."; return }

    Write-SetupLog "Setting up PowerShell profile: $PROFILE_FILE"
    $profileDir = Split-Path $PROFILE_FILE -Parent
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

    $profileContent = @'
# ==========================================
#   MY CUSTOM POWERSHELL PROFILE
# ==========================================

# ==========================================
#   MY CUSTOM POWERSHELL PROFILE
# ==========================================

# --- 1. Navigation & Listing ---
Set-Alias c        Clear-Host
function home  { Set-Location $HOME }  # Fix: Changed Set-Alias to function to accept arguments
Set-Alias ll       Get-ChildItem   
function ..    { Set-Location .. }
function ...   { Set-Location ..\.. }
function .3    { Set-Location ..\..\.. }
function la    { Get-ChildItem -Force }
function l     { Get-ChildItem }



# --- 3. Git Workflow ---
function gs    { git status }
function ga    { git add . }
function gc    { git commit -m $args }
function gp    { git push }
function gpl   { git pull }
function gd    { git diff }
function gb    { git branch }
function gco   { git checkout }
function glog  { git log --oneline --graph --decorate }
function gcl   { git clone $args }
function untrack  { git rm --cached $args }
function unstage  { git restore --staged $args }
function undo     { git reset --soft HEAD~1 }
function hist     { git log --graph --abbrev-commit --decorate --all }
function publish  { gh repo create --public --push --source=. }
function ignored  { git status --ignored -s | Select-String "!!" }
function why      { git check-ignore -v $args }

# --- 4. Python & Development (Windows) ---
Set-Alias py    py        # Python launcher
Set-Alias pip   pip
function venv   { py -m venv .venv }
function act    { .\.venv\Scripts\Activate.ps1 }   # activate venv
Set-Alias deact  Deactivate -ErrorAction SilentlyContinue

# --- 5. System Maintenance (winget based) ---
function update  { winget upgrade --all }
function install { winget install $args }
function search  { winget search $args }
function remove  { winget uninstall $args }

# --- 6. Search ---
function grep   { Select-String $args }
function ports  { Get-NetTCPConnection -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess }

# --- 7. Networking ---
function myip   { (Invoke-RestMethod https://api.ipify.org) }

# --- 8. Open current folder in Explorer ---
function open    { explorer.exe . }

# ==========================================
#  run <filename> — compile/execute by extension
# ==========================================
function run {
    param([string]$f)
    if (-not $f) { Write-Host "Usage: run <filename>" -ForegroundColor Red; return }
    if (-not (Test-Path $f)) { Write-Host "Error: File '$f' not found!" -ForegroundColor Red; return }

    $ext = [System.IO.Path]::GetExtension($f).TrimStart('.').ToLower()
    $base = [System.IO.Path]::GetFileNameWithoutExtension($f)
    $dir  = [System.IO.Path]::GetDirectoryName($f); if (-not $dir) { $dir = (Get-Location).Path }

    Write-Host "[Analysis] Running .$ext file: $f" -ForegroundColor Blue
    switch ($ext) {
        "c"    { pushd $dir; gcc -Wall -Wextra -pthread "$f" -o "$base.exe"; if ($?) { .\$base.exe }; popd }
        "cpp"  { pushd $dir; g++ -Wall -Wextra -pthread -std=c++23 "$f" -o "$base.exe"; if ($?) { .\$base.exe }; popd }
        "py"   { python $f }
        "js"   { node $f }
        "ps1"  { & $f }
        "sh"   { bash $f }
        default { Write-Host "Unsupported extension: .$ext" -ForegroundColor Red }
    }
}

# ==========================================
#  newrepo <name> — init + commit + push + open VS Code
# ==========================================
function newrepo {
    param([string]$name)
    if (-not $name) { Write-Host "Error: Please provide a project name." -ForegroundColor Red; return }
    if (Test-Path $name) { Write-Host "Error: Directory '$name' already exists." -ForegroundColor Red; return }

    Write-Host "[Analysis] Initializing environment for '$name'..." -ForegroundColor Blue
    New-Item -ItemType Directory -Path $name -Force | Out-Null
    Set-Location $name
    "# $name" | Set-Content README.md -Encoding UTF8

    git init | Out-Null
    git add .
    git commit -m "Initial commit" | Out-Null

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh repo create "$name" --public --push --source=.
        Write-Host "[OK] '$name' is live on GitHub." -ForegroundColor Green
    } else {
        Write-Host "Warning: GitHub CLI (gh) not found. Repo not pushed." -ForegroundColor Red
    }

    if (Get-Command code -ErrorAction SilentlyContinue) { code . }
}

# ==========================================
#  delrepo — delete remote +/or local repo
# ==========================================
function delrepo {
    if (-not (Test-Path .git)) { Write-Host "Error: Not inside a Git repository." -ForegroundColor Red; return }

    $repo_name = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
    $local_path = (Get-Location).Path

    if (-not $repo_name) {
        Write-Host "Error: Failed to fetch remote repository info." -ForegroundColor Red
        return
    }

    Write-Host "Target Remote Repository: $repo_name"
    Write-Host "Target Local Directory: $local_path"
    Write-Host "-------------------------------------"

    $del_remote = Read-Host "Delete remote repository? (y/n)"
    $del_local  = Read-Host "Delete local folder? (y/n)"

    if ($del_remote -match '^[Yy]') {
        Write-Host "Deleting remote repository..."
        gh repo delete "$repo_name" --yes
        Write-Host "[OK] Remote repository deleted." -ForegroundColor Green
    } else {
        Write-Host "Skipped remote repository deletion."
    }

    if ($del_local -match '^[Yy]') {
        Write-Host "Deleting local folder..."
        Set-Location ..
        Remove-Item -Recurse -Force $local_path
        Write-Host "[OK] Local folder deleted." -ForegroundColor Green
    } else {
        Write-Host "Skipped local folder deletion."
    }
}

# ==========================================
#  gpub — init + commit + push current folder via gh
# ==========================================
function gpub {
    if (-not (Test-Path .git)) { git init | Out-Null }
    $repo_name = (Split-Path -Leaf (Get-Location))
    git add .
    git commit -m "Initial commit" | Out-Null
    gh repo create "$repo_name" --public --source=. --push
    if ($?) { Write-Host "[OK] $repo_name is now live!" -ForegroundColor Green }
}

# ==========================================
#  gup — add/commit/push with message
# ==========================================
function gup {
    param([string]$m)
    if (-not (Test-Path .git)) { Write-Host "[X] Error: Not a Git repo." -ForegroundColor Red; return }
    git add .
    $msg = if ($m) { $m } else { "Updates" }
    git commit -m $msg | Out-Null
    if ($?) {
        git push
        Write-Host "[OK] Success: Pushed to GitHub!" -ForegroundColor Green
    } else {
        Write-Host "[!] No changes to commit."
    }
}

# ==========================================
#  dpub — build + push Docker image to GHCR
# ==========================================
function dpub {
    param([string]$app_name, [string]$tag = "latest")
    if (-not $app_name) { $app_name = (Split-Path -Leaf (Get-Location)).ToLower() }

    if (-not (Test-Path Dockerfile)) { Write-Host "[X] Error: No Dockerfile found." -ForegroundColor Red; return }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host "[X] Error: GitHub CLI (gh) is not installed." -ForegroundColor Red; return }

    Write-Host "[OK] Fetching GitHub username..." -ForegroundColor Blue
    $gh_user = (gh api user -q ".login").ToLower()
    $full_image = "ghcr.io/$gh_user/$app_name`:$tag"

    Write-Host "[OK] Building Docker image: $app_name..." -ForegroundColor Blue
    docker build -t "$app_name" .
    if (-not $?) { Write-Host "[X] Error: Docker build failed." -ForegroundColor Red; return }

    Write-Host "[OK] Tagging image..." -ForegroundColor Blue
    docker tag "$app_name" "$full_image"

    Write-Host "[OK] Pushing to GHCR: $full_image..." -ForegroundColor Blue
    if (docker push "$full_image") {
        Write-Host "[OK] Success: Image published to $full_image" -ForegroundColor Green
    } else {
        Write-Host "[X] Error: Docker push failed. Authenticated with GHCR?" -ForegroundColor Red
    }
}


'@

    Set-Content -Path $PROFILE_FILE -Value $profileContent -Encoding UTF8
    Write-SetupLog "Profile written to $PROFILE_FILE"
    Write-SetupLog "Run: . $PROFILE_FILE   (or reopen PowerShell) to activate aliases." -Color Blue
    Write-Host "[SETUP] PowerShell profile loaded. Type 'c' to clear, 'gs' for git status." -ForegroundColor Green
}

# ============================================================
#  Summary
# ============================================================
# ============================================================
#  Summary
# ============================================================
function Show-Summary {
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "         INSTALLATION SUMMARY" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green

    $git = if (Get-Command git -ErrorAction SilentlyContinue) { git --version 2>$null }
    Write-Host "Git:      $(if ($git) { $git } else { 'not found' })"

    $rust = if (Get-Command rustc -ErrorAction SilentlyContinue) { rustc --version 2>$null }
    Write-Host "Rust:     $(if ($rust) { $rust.Split(' ')[1] } else { 'not installed' })"

    $node = if (Get-Command node -ErrorAction SilentlyContinue) { node --version 2>$null }
    Write-Host "Node:     $(if ($node) { $node } else { 'not installed' })"

    $npm = if (Get-Command npm -ErrorAction SilentlyContinue) { npm --version 2>$null }
    Write-Host "NPM:      $(if ($npm) { $npm } else { 'not installed' })"
    
    $py = if (Get-Command py.exe -ErrorAction SilentlyContinue) { py.exe --version 2>$null }
    Write-Host "Python:   $(if ($py) { $py } else { 'not installed' })"

    $gh = if (Get-Command gh -ErrorAction SilentlyContinue) { gh --version 2>$null }
    Write-Host "GH CLI:   $(if ($gh) { ($gh | Select-Object -First 1).Split(' ')[2] } else { 'not installed' })"

    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Setup Complete!" -ForegroundColor Green
}

# ============================================================
#  --- Execution ---
# ============================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Windows 11 Pro Dev Environment Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Enable this line only if your machine policy blocks script execution:
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 1. Git suite (active by default)
Install-GitSuite

# 2. Shell profile with aliases & functions (active by default)
Set-Profile

# --- Optional tools: uncomment the ones you want ---
# if (-not $SkipWinget) {
#     Install-WingetPackage -Id "GitHub.cli" -CheckCmd "gh" -Name "GitHub CLI"
#     Install-WingetPackage -Id "OpenJS.NodeJS.LTS" -CheckCmd "node" -Name "Node.js LTS"
# }
# Install-Rust
# New-SshKey
# Install-GhCli   # includes GHCR docker login

Show-Summary

Write-Host ""
Write-Host "To activate your new aliases, run:" -ForegroundColor Cyan
Write-Host "  . $PROFILE_FILE" -ForegroundColor Cyan
Write-Host ""
