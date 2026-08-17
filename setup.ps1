# ==============================================================================
# File: setup.ps1
# Description: Universal Cross-Version PowerShell Custom Scripts Engine
# ==============================================================================

try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue } catch {}

# Sync across both PowerShell 7+ (PowerShell) and Windows PowerShell 5.1 (WindowsPowerShell)
$docs = [Environment]::GetFolderPath("MyDocuments")
$scriptLocations = @(
    (Join-Path $docs "PowerShell\CustomScripts"),
    (Join-Path $docs "WindowsPowerShell\CustomScripts")
)
$profileLocations = @(
    (Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1"),
    (Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
)

# Initialize directories
foreach ($dir in $scriptLocations) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

# ==============================================================================
# 1. CORE INSTALLER ENGINE
# ==============================================================================
function global:Install-PSScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$Target,
        [Parameter(Position = 1)]
        [string]$Name
    )

    process {
        $docs = [Environment]::GetFolderPath("MyDocuments")
        $targetDirs = @(
            (Join-Path $docs "PowerShell\CustomScripts"),
            (Join-Path $docs "WindowsPowerShell\CustomScripts")
        )

        # Fixed: Pass valid [char[]] array to .Trim()
        $trimChars = @('"', "'", ' ', "`t", "`r", "`n")
        $cleanTarget = $Target.Trim($trimChars)
        
        $isFile = ($cleanTarget -notmatch "[\r\n]") -and (Test-Path -LiteralPath $cleanTarget -PathType Leaf -ErrorAction Ignore)

        if ($isFile) {
            $src = (Resolve-Path -LiteralPath $cleanTarget).Path
            $fn  = if ($Name) { ($Name -replace '\.ps1$', '') + '.ps1' } else { Split-Path $src -Leaf }
            foreach ($d in $targetDirs) { Copy-Item -LiteralPath $src -Destination (Join-Path $d $fn) -Force }
        } else {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanTarget)
                $hash  = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '')
                $Name  = "Injected_$($hash.Substring(0, 8))"
            }
            $fn = ($Name -replace '\.ps1$', '') + '.ps1'
            $payload = $Target -replace '(?i)\bfunction\s+(?!global:)([a-zA-Z0-9_-]+)', 'function global:$1'
            foreach ($d in $targetDirs) { Set-Content -Path (Join-Path $d $fn) -Value $payload -Encoding UTF8 -Force }
        }

        # Load into active session
        $activeDest = Join-Path $targetDirs[0] $fn
        if (Test-Path $activeDest) {
            Unblock-File -LiteralPath $activeDest -ErrorAction Ignore
            . $activeDest
        }
        Write-Host "[+] Installed & Synced: $fn" -ForegroundColor Green
    }
}
Set-Alias inps Install-PSScript -Scope Global

# ==============================================================================
# 2. PROFILE EMBEDDING (Dual-Version)
# ==============================================================================
$engineCode = @'
# ==========================================
# POWERSHELL CUSTOM SCRIPT MANAGER & LOADER
# ==========================================
$scriptDir = Join-Path (Split-Path -Parent $PROFILE) "CustomScripts"
if (Test-Path $scriptDir) {
    Get-ChildItem -Path $scriptDir -Filter '*.ps1' | ForEach-Object {
        Unblock-File -LiteralPath $_.FullName -ErrorAction Ignore
        . $_.FullName
    }
}

function global:Install-PSScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$Target,
        [Parameter(Position = 1)]
        [string]$Name
    )
    process {
        $docs = [Environment]::GetFolderPath("MyDocuments")
        $targetDirs = @(
            (Join-Path $docs "PowerShell\CustomScripts"),
            (Join-Path $docs "WindowsPowerShell\CustomScripts")
        )
        $trimChars = @('"', "'", ' ', "`t", "`r", "`n")
        $cleanTarget = $Target.Trim($trimChars)
        $isFile = ($cleanTarget -notmatch "[\r\n]") -and (Test-Path -LiteralPath $cleanTarget -PathType Leaf -ErrorAction Ignore)

        if ($isFile) {
            $src = (Resolve-Path -LiteralPath $cleanTarget).Path
            $fn  = if ($Name) { ($Name -replace '\.ps1$', '') + '.ps1' } else { Split-Path $src -Leaf }
            foreach ($d in $targetDirs) { 
                if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
                Copy-Item -LiteralPath $src -Destination (Join-Path $d $fn) -Force 
            }
        } else {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanTarget)
                $hash  = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '')
                $Name  = "Injected_$($hash.Substring(0, 8))"
            }
            $fn = ($Name -replace '\.ps1$', '') + '.ps1'
            $payload = $Target -replace '(?i)\bfunction\s+(?!global:)([a-zA-Z0-9_-]+)', 'function global:$1'
            foreach ($d in $targetDirs) { 
                if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
                Set-Content -Path (Join-Path $d $fn) -Value $payload -Encoding UTF8 -Force 
            }
        }
        $activeDest = Join-Path (Split-Path -Parent $PROFILE) "CustomScripts\$fn"
        if (Test-Path $activeDest) {
            Unblock-File -LiteralPath $activeDest -ErrorAction Ignore
            . $activeDest
        }
        Write-Host "[+] Installed & Loaded: $fn" -ForegroundColor Green
    }
}
Set-Alias inps Install-PSScript -Scope Global
# ==========================================
'@

foreach ($prof in $profileLocations) {
    $parent = Split-Path -Parent $prof
    if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $prof)) { New-Item -Path $prof -ItemType File -Force | Out-Null }
    
    $profContent = Get-Content -LiteralPath $prof -Raw -ErrorAction Ignore
    if ($profContent -match 'POWERSHELL CUSTOM SCRIPT MANAGER') {
        $profContent = $profContent -replace '(?s)# ==========================================.*?# ==========================================', ''
    }
    Set-Content -LiteralPath $prof -Value ($profContent.Trim() + "`n" + $engineCode) -Encoding UTF8 -Force
}

# ==============================================================================
# 3. DEFAULT TOOLS REGISTRATION
# ==============================================================================

# Tool: IP Checker
Install-PSScript @'
function ip {
    Write-Host "[ Public IP ]" -ForegroundColor Cyan
    try { 
        $pub = (Invoke-RestMethod ifconfig.me/ip -TimeoutSec 3).Trim()
        Write-Host $pub -ForegroundColor Green 
    } 
    catch { Write-Host "Offline / Unreachable" -ForegroundColor Red }
    
    Write-Host "`n[ Local & Virtual IPs ]" -ForegroundColor Cyan
    Get-NetIPAddress -AddressFamily IPv4 | 
        Where-Object { $_.IPAddress -ne '127.0.0.1' } | 
        Sort-Object InterfaceAlias | 
        Select-Object @{Name="Adapter Name";Expression={$_.InterfaceAlias}}, 
                      @{Name="IP Address";Expression={$_.IPAddress}} | 
        Format-Table -AutoSize
}
'@ -Name "Alias-ip"

# Tool: Background Process Manager
Install-PSScript @'
function Invoke-Bg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target,
        [Parameter(Position = 1)]
        [string]$Arguments = "",
        [switch]$HideWindow,
        [switch]$Stop,
        [switch]$Restart,
        [switch]$Info
    )

    if ($Info) {
        $fileName = [System.IO.Path]::GetFileName($Target)
        $procBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Target)
        
        $matched = Get-CimInstance Win32_Process | Where-Object {
            ($_.CommandLine -like "*$fileName*") -or ($_.Name -eq "$procBaseName.exe") -or ($_.Name -eq $Target) -or ($_.ProcessId -eq $Target)
        }
        
        if ($matched) {
            $matched | ForEach-Object {
                $sysProc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                [PSCustomObject]@{
                    PID     = $_.ProcessId
                    Name    = $_.Name
                    RAM_MB  = if ($sysProc) { [math]::Round($sysProc.WorkingSet / 1MB, 2) } else { "N/A" }
                    CPU_Sec = if ($sysProc) { [math]::Round($sysProc.CPU, 2) } else { "N/A" }
                    Command = $_.CommandLine
                }
            } | Format-Table -AutoSize
        } else {
            Write-Host "No active process found matching: $Target" -ForegroundColor Yellow
        }
        return
    }

    if ($Stop -or $Restart) {
        if ($Target -match '^\d+$') {
            Stop-Process -Id ([int]$Target) -Force -ErrorAction SilentlyContinue
            Write-Host "Killed PID: $Target" -ForegroundColor Green
        } else {
            $fileName = [System.IO.Path]::GetFileName($Target)
            $procBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Target)
            
            $matched = Get-CimInstance Win32_Process | Where-Object {
                ($_.CommandLine -like "*$fileName*") -or ($_.Name -eq "$procBaseName.exe") -or ($_.Name -eq $Target)
            }
            if ($matched) {
                foreach ($p in $matched) {
                    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                    Write-Host "Terminated [$($p.Name)] (PID: $($p.ProcessId))" -ForegroundColor Green
                }
            }
        }
        if ($Stop) { return }
    }

    $resolvedPath = if (Test-Path $Target) { (Resolve-Path $Target).Path } else { $Target }
    $workingDir = if (Test-Path $resolvedPath) { Split-Path $resolvedPath } else { (Get-Location).Path }
    $ext = [System.IO.Path]::GetExtension($resolvedPath).ToLower()

    $runner = $resolvedPath
    $argList = $Arguments

    switch ($ext) {
        { $_ -in ".exe", ".com" } { $runner = $resolvedPath; if ($HideWindow) { $HideWindow = $true } }
        { $_ -in ".cpp", ".cc", ".cxx" } {
            $tempExe = [System.IO.Path]::ChangeExtension($resolvedPath, "exe")
            g++ -O3 -mwindows "$resolvedPath" -o "$tempExe" -lgdi32
            $runner = $tempExe
        }
        ".cs"   { $runner = "dotnet"; $argList = "script `"$resolvedPath`" -- $Arguments".Trim(); $HideWindow = $true }
        { $_ -in ".py", ".pyw" } { $runner = "pythonw.exe"; $argList = "`"$resolvedPath`" $Arguments".Trim() }
        ".js"   { $runner = "node";   $argList = "`"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".ts"   { $runner = "npx";    $argList = "tsx `"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".ps1"  { $runner = "powershell.exe"; $argList = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$resolvedPath`" $Arguments".Trim() }
        ".bat"  { $runner = "cmd.exe"; $argList = "/c `"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".cmd"  { $runner = "cmd.exe"; $argList = "/c `"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".sh"   { $runner = "wsl.exe"; $argList = "bash -c '`"$resolvedPath`" $Arguments'".Trim(); $HideWindow = $true }
        ".go"   { $runner = "go"; $argList = "run `"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".rs"   { $runner = "cargo"; $argList = "run --quiet --manifest-path `"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".jar"  { $runner = "javaw"; $argList = "-jar `"$resolvedPath`" $Arguments".Trim() }
        ".java" { $runner = "java"; $argList = "`"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".rb"   { $runner = "rubyw"; $argList = "`"$resolvedPath`" $Arguments".Trim() }
        ".php"  { $runner = "php"; $argList = "`"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        ".lua"  { $runner = "lua"; $argList = "`"$resolvedPath`" $Arguments".Trim(); $HideWindow = $true }
        default { $runner = $resolvedPath }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $runner
    $psi.Arguments = $argList
    $psi.WorkingDirectory = $workingDir
    $psi.UseShellExecute = $true

    if ($HideWindow) {
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
    }

    $proc = [System.Diagnostics.Process]::Start($psi)

    [PSCustomObject]@{
        ProcessName = $proc.ProcessName
        PID         = $proc.Id
        Runner      = $runner
        Target      = $resolvedPath
        Status      = "Running"
    } | Format-Table -AutoSize
}

Set-Alias bg Invoke-Bg -Scope Global
'@ -Name "Alias-bg"

Write-Host "`n[SUCCESS] Setup complete. Engine and default tools synced for all PowerShell environments." -ForegroundColor Cyan