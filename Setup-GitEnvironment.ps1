function Setup-GitEnvironment {
    param (
        [string]$UserName = "Cyber Arghya",
        [string]$UserEmail = "workarghya@gmail.com"
    )

    # 1. Install Git & GitHub CLI via winget if missing
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Git..." -ForegroundColor Cyan
        winget install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    } else {
        Write-Host "Git: Already installed. Skipping." -ForegroundColor Yellow
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "Installing GitHub CLI (gh)..." -ForegroundColor Cyan
        winget install -e --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements
    } else {
        Write-Host "GitHub CLI: Already installed. Skipping." -ForegroundColor Yellow
    }

    # Refresh session PATH for immediate CLI access
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # 2. Configure Git Global Identity & Core Defaults
    Write-Host "Configuring Git Global Settings..." -ForegroundColor Cyan
    git config --global user.name "$UserName"
    git config --global user.email "$UserEmail"
    git config --global init.defaultBranch main
    git config --global core.autocrlf true
    git config --global pull.rebase false

    # 3. Setup Global .gitignore
    $globalIgnorePath = "$env:USERPROFILE\.gitignore_global"
    if (-not (Test-Path $globalIgnorePath)) {
        Write-Host "Creating Global .gitignore..." -ForegroundColor Cyan
        $ignoreContent = @"
# OS Metadata
.DS_Store
Thumbs.db
desktop.ini

# Editors & IDEs
.vscode/
.idea/
*.suo
*.user
*.userosset
*.sln.docstates

# Node & Package Managers
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*

# Python
__pycache__/
*.py[cod]
*$py.class
.venv/
env/
venv/

# Rust / C++ Build Artifacts
target/
*.exe
*.o
*.obj
*.dll

# Environment & Secrets
.env
.env.local
.env.*.local
*.pem
*.key
"@
        Set-Content -Path $globalIgnorePath -Value $ignoreContent -Encoding UTF8
        git config --global core.excludesfile "$globalIgnorePath"
        Write-Host "SUCCESS: Global .gitignore configured." -ForegroundColor Green
    } else {
        Write-Host "Global .gitignore: Already exists. Skipping." -ForegroundColor Yellow
    }

    # 4. SSH Key Setup (Ed25519)
    $sshDir = "$env:USERPROFILE\.ssh"
    $keyPath = "$sshDir\id_ed25519"
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }

    if (-not (Test-Path $keyPath)) {
        Write-Host "Generating SSH Key (Ed25519)..." -ForegroundColor Cyan
        ssh-keygen -t ed25519 -C "$UserEmail" -f "$keyPath" -N '""'
        
        # Ensure ssh-agent service is running and add key
        Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service ssh-agent -ErrorAction SilentlyContinue
        & ssh-add "$keyPath" 2>$null
        Write-Host "SUCCESS: SSH key created at $keyPath" -ForegroundColor Green
    } else {
        Write-Host "SSH Key (id_ed25519): Already exists. Skipping." -ForegroundColor Yellow
    }

    # 5. GHCR (GitHub Container Registry) Login Check / Auth Prep
    Write-Host "Checking GitHub CLI Auth & GHCR..." -ForegroundColor Cyan
    $ghAuthStatus = gh auth status 2>&1
    if ($ghAuthStatus -match "Logged in to") {
        # Export PAT / token from GitHub CLI into Docker for GHCR
        try {
            $ghToken = gh auth token 2>$null
            if ($ghToken -and (Get-Command docker -ErrorAction SilentlyContinue)) {
                $ghToken | docker login ghcr.io -u "$UserName" --password-stdin 2>$null
                Write-Host "SUCCESS: Docker authenticated to ghcr.io via gh token." -ForegroundColor Green
            }
        } catch {
            Write-Host "GHCR Login skipped (Docker daemon offline or non-interactive)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Note: Run 'gh auth login' with 'read:packages, write:packages' scope to complete GHCR integration." -ForegroundColor Yellow
    }

    # 6. Verification Summary
    function Get-ToolVersion ($cmd) {
        try {
            $output = Invoke-Expression $cmd 2>$null
            if ($output) { return ($output | Select-Object -First 1).ToString().Trim() }
        } catch {}
        return "Not Found / Not Configured"
    }

    Write-Host "`n================ GIT ECOSYSTEM SUMMARY ================" -ForegroundColor Magenta
    [PSCustomObject]@{
        "Component"        = "Git CLI"
        "Status / Value"   = Get-ToolVersion "git --version"
    },
    [PSCustomObject]@{
        "Component"        = "GitHub CLI (gh)"
        "Status / Value"   = Get-ToolVersion "gh --version"
    },
    [PSCustomObject]@{
        "Component"        = "User Name"
        "Status / Value"   = Get-ToolVersion "git config --global user.name"
    },
    [PSCustomObject]@{
        "Component"        = "User Email"
        "Status / Value"   = Get-ToolVersion "git config --global user.email"
    },
    [PSCustomObject]@{
        "Component"        = "Global .gitignore"
        "Status / Value"   = if (Test-Path $globalIgnorePath) { $globalIgnorePath } else { "Missing" }
    },
    [PSCustomObject]@{
        "Component"        = "SSH Public Key"
        "Status / Value"   = if (Test-Path "$keyPath.pub") { "$keyPath.pub (Present)" } else { "Missing" }
    } | Format-Table -AutoSize

    Write-Host "Git Ecosystem Setup Complete!`n" -ForegroundColor Green
}

Setup-GitEnvironment