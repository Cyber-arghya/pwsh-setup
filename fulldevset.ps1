# Production-ready Windows dev environment bootstrapper
function Setup-DevelopmentEnvironment {
    [CmdletBinding()]
    param (
        [string]$UserName  = "Cyber Arghya",
        [string]$UserEmail = "workarghya@gmail.com"
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warning "Running in non-elevated mode. System-wide configurations will target CurrentUser."
    }

    # 1. PATH Synchronization Helper
    function Update-SessionPath {
        $targets = @(
            [Environment]::GetEnvironmentVariable("Path", "Machine"),
            [Environment]::GetEnvironmentVariable("Path", "User"),
            "$env:USERPROFILE\.cargo\bin",
            "$env:ProgramFiles\Docker\Docker\resources\bin",
            "$env:ProgramFiles\Git\cmd",
            "C:\msys64\ucrt64\bin",
            "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts",
            "$env:LOCALAPPDATA\Programs\Python\Python312"
        )
        $validPaths = ($targets -join ";") -split ";" | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
        $env:Path = $validPaths -join ";"
    }

    # 2. Resilient Package Installer
    function Install-Pkg ($name, $id, $cmd, $path = $null) {
        $installed = if ($path) { Test-Path $path } elseif ($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) } else { $false }
        if (-not $installed) {
            Write-Host "Installing $name..." -ForegroundColor Cyan
            winget install -e --id $id --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
            Update-SessionPath
        } else {
            Write-Host "$name : Installed" -ForegroundColor Green
        }
    }

    # 3. Tooling Matrix
    $packages = @(
        @{ Name = "VS Code";        Id = "Microsoft.VisualStudioCode";      Cmd = "code";   Path = $null },
        @{ Name = "Git";            Id = "Git.Git";                         Cmd = "git";    Path = "$env:ProgramFiles\Git\cmd\git.exe" },
        @{ Name = "GitHub CLI";     Id = "GitHub.cli";                      Cmd = "gh";     Path = $null },
        @{ Name = "MSYS2";          Id = "MSYS2.MSYS2";                     Cmd = $null;    Path = "C:\msys64\usr\bin\bash.exe" },
        @{ Name = "OpenJDK 21";     Id = "EclipseAdoptium.Temurin.21.JDK";  Cmd = "java";   Path = "$env:ProgramFiles\Eclipse Adoptium" },
        @{ Name = "Node.js (LTS)";  Id = "OpenJS.NodeJS.LTS";               Cmd = "node";   Path = $null },
        @{ Name = "Python 3.12";    Id = "Python.Python.3.12";              Cmd = "python"; Path = "$env:LOCALAPPDATA\Programs\Python" },
        @{ Name = "Rustup";         Id = "Rustlang.Rustup";                 Cmd = "rustc";  Path = "$env:USERPROFILE\.cargo\bin\rustc.exe" },
        @{ Name = "Docker Desktop"; Id = "Docker.DockerDesktop";            Cmd = "docker"; Path = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe" }
    )
    foreach ($pkg in $packages) { Install-Pkg $pkg.Name $pkg.Id $pkg.Cmd $pkg.Path }

    # 4. MSYS2 UCRT64 GCC Setup
    if (Test-Path "C:\msys64\usr\bin\bash.exe") {
        if (-not (Test-Path "C:\msys64\ucrt64\bin\gcc.exe")) {
            Write-Host "Provisioning GCC via MSYS2..." -ForegroundColor Cyan
            & "C:\msys64\usr\bin\bash.exe" -lc "pacman -Sy --noconfirm mingw-w64-ucrt-x86_64-gcc" | Out-Null
        }
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notmatch [regex]::Escape("C:\msys64\ucrt64\bin")) {
            $updatedUserPath = (($userPath, "C:\msys64\ucrt64\bin" -split ";") | Where-Object { $_ } | Select-Object -Unique) -join ";"
            [Environment]::SetEnvironmentVariable("Path", $updatedUserPath, "User")
        }
    }

    # 5. Environment Variables Configuration (JAVA_HOME)
    $jdkDir = "$env:ProgramFiles\Eclipse Adoptium"
    if (Test-Path $jdkDir) {
        $jdk = Get-ChildItem $jdkDir -Filter "jdk-*" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($jdk) {
            $scope = if ($isAdmin) { "Machine" } else { "User" }
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $jdk, $scope)
            $env:JAVA_HOME = $jdk
        }
    }
    Update-SessionPath

    # 6. Git Identity, Core Config & SSH Infrastructure
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git config --global user.name "$UserName"
        git config --global user.email "$UserEmail"
        git config --global init.defaultBranch main
        git config --global core.autocrlf true
        git config --global pull.rebase false

        $globalIgnore = "$env:USERPROFILE\.gitignore_global"
        if (-not (Test-Path $globalIgnore)) {
            @'
.DS_Store
Thumbs.db
desktop.ini
.vscode/
.idea/
*.suo
.venv/
env/
venv/
.env*
node_modules/
target/
__pycache__/
*.exe
*.o
*.obj
*.dll
*.key
*.pem
'@ | Set-Content -Path $globalIgnore -Encoding UTF8
            git config --global core.excludesfile "$globalIgnore"
        }
    }

    $sshDir = "$env:USERPROFILE\.ssh"
    $keyPath = "$sshDir\id_ed25519"
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
    if (-not (Test-Path $keyPath)) {
        ssh-keygen -t ed25519 -C "$UserEmail" -f "$keyPath" -N '""'
        if ($isAdmin) {
            Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service ssh-agent -ErrorAction SilentlyContinue
            & ssh-add "$keyPath" 2>$null
        }
    }

    # GHCR / Docker Auth Bridge
    if ((Get-Command gh -ErrorAction SilentlyContinue) -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        if ((gh auth status 2>&1) -match "Logged in to") {
            $ghToken = gh auth token 2>$null
            if ($ghToken) {
                $ghToken | docker login ghcr.io -u "$UserName" --password-stdin 2>$null
            }
        }
    }

    # 7. VS Code Extensions Setup
    if (Get-Command code -ErrorAction SilentlyContinue) {
        $exts = @(
            "formulahendry.code-runner", "eamodio.gitlens", "pkief.material-icon-theme",
            "ms-vscode.cpptools", "ms-vscode.cpptools-extension-pack", "ms-vscode.cmake-tools",
            "vscjava.vscode-java-pack", "dbaeumer.vscode-eslint", "esbenp.prettier-vscode",
            "christian-kohler.npm-intellisense", "christian-kohler.path-intellisense",
            "ms-python.python", "ms-python.vscode-pylance", "ms-python.black-formatter",
            "rust-lang.rust-analyzer", "tamasfe.even-better-toml", "vadimcn.vscode-lldb",
            "ms-azuretools.vscode-docker", "redhat.vscode-yaml", "gruntfuggly.todo-tree"
        )
        $installedExts = & code --list-extensions 2>$null
        foreach ($ext in $exts) {
            if ($installedExts -notcontains $ext) { & code --install-extension $ext --force | Out-Null }
        }

        # 8. VS Code User Settings
        $cfgDir  = "$env:APPDATA\Code\User"
        $cfgFile = "$cfgDir\settings.json"
        if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }

        @'
{
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": "active",
  "editor.tabSize": 2,
  "workbench.iconTheme": "material-icon-theme",
  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "code-runner.runInTerminal": true,
  "code-runner.saveFileBeforeRun": true,
  "code-runner.clearPreviousOutput": true,
  "code-runner.preserveFocus": false,
  "code-runner.executorMap": {
    "powershell": "powershell -ExecutionPolicy ByPass -File \"$fileName\"",
    "c": "cd $dir; gcc $fileName -o $fileNameWithoutExt -Wall -Wextra -pthread -std=c17; .\\\"$fileNameWithoutExt\\\"; Remove-Item -Force \\\".\\$fileNameWithoutExt.exe\\\" -ErrorAction SilentlyContinue",
    "cpp": "cd $dir; g++ $fileName -o $fileNameWithoutExt -Wall -Wextra -pthread -std=c++23; .\\\"$fileNameWithoutExt\\\"; Remove-Item -Force \\\".\\$fileNameWithoutExt.exe\\\" -ErrorAction SilentlyContinue",
    "rust": "cd $dir; rustc $fileName -o $fileNameWithoutExt; .\\\"$fileNameWithoutExt\\\"; Remove-Item -Force \\\".\\$fileNameWithoutExt.exe\\\", \\\".\\$fileNameWithoutExt.pdb\\\" -ErrorAction SilentlyContinue",
    "java": "cd $dir; javac -encoding UTF-8 $fileName; java $fileNameWithoutExt; Remove-Item -Force \\\".\\$fileNameWithoutExt.class\\\" -ErrorAction SilentlyContinue",
    "python": "cd $dir; python -u $fileName",
    "javascript": "node $fileName",
    "typescript": "npx tsx $fileName",
    "go": "cd $dir; go run $fileName",
    "php": "php $fileName",
    "shellscript": "bash $fileName",
    "bat": "cmd /c $fileName",
    "html": "explorer.exe $fileName"
  },
  "[python]": {
    "editor.defaultFormatter": "ms-python.black-formatter",
    "editor.formatOnSave": true
  },
  "[c]": {
    "editor.defaultFormatter": "ms-vscode.cpptools"
  },
  "[cpp]": {
    "editor.defaultFormatter": "ms-vscode.cpptools"
  },
  "editor.suggestSelection": "first",
  "editor.cursorBlinking": "smooth",
  "editor.smoothScrolling": true,
  "editor.linkedEditing": true,
  "editor.wordWrap": "on",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.encoding": "utf8",
  "C_Cpp.default.cppStandard": "c++23",
  "C_Cpp.default.cStandard": "c17"
}
'@ | Set-Content -Path $cfgFile -Encoding UTF8 -Force
    }

    # 9. Audit & Verification Table
    $audit = [ordered]@{
        "VS Code"        = { code --version }
        "Git"            = { git --version }
        "GitHub CLI"     = { gh --version }
        "GCC (C/C++)"    = { & "C:\msys64\ucrt64\bin\gcc.exe" --version }
        "Java"           = { java --version }
        "Node.js"        = { node --version }
        "Python"         = { python --version }
        "Rust"           = { rustc --version }
        "Docker"         = { docker --version }
        "Git User"       = { git config --global user.name }
        "Git Email"      = { git config --global user.email }
        "SSH Key"        = { if (Test-Path "$keyPath.pub") { "Present (ed25519)" } else { "Missing" } }
    }

    Write-Host "`n================ ENVIRONMENT STATUS ================" -ForegroundColor Magenta
    $audit.GetEnumerator() | ForEach-Object {
        $val = try { (& $_.Value 2>$null | Select-Object -First 1).ToString().Trim() } catch { $null }
        [PSCustomObject]@{
            Component = $_.Key
            Status    = if ($val) { $val } else { "Not Found / Offline" }
        }
    } | Format-Table -AutoSize
}

# Run
Setup-DevelopmentEnvironment
