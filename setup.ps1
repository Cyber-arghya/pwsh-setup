# ==========================================
# File: setup.ps1
# Description: Bulletproof Architecture (Embeds engine directly in Profile)
# ==========================================

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

$engineCode = @'

# ==========================================
# POWERSHELL CUSTOM SCRIPT MANAGER
# ==========================================
function global:Install-PSScript {
    param([Parameter(Mandatory=$true, ValueFromPipeline=$true)][string]$Target, [string]$Name)
    process {
        $scriptDir = Join-Path (Split-Path $PROFILE) "CustomScripts"
        if (-not (Test-Path $scriptDir)) { New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null }
        
        $c = $Target.Trim('"','''',' ')
        $isFile = ($c -notmatch "`n") -and (Test-Path -LiteralPath $c -PathType Leaf -ErrorAction Ignore)
        
        if ($isFile) {
            $src = (Resolve-Path $c).Path
            $fn = if ($Name) { ($Name -replace '\.ps1$','') + ".ps1" } else { Split-Path $src -Leaf }
            $destFile = Join-Path $scriptDir $fn
            Copy-Item -LiteralPath $src -Destination $destFile -Force
        } else {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                $b = [System.Text.Encoding]::UTF8.GetBytes($c)
                $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($b)).Replace('-','')
                $Name = "Injected_$($hash.Substring(0,8))"
            }
            $fn = ($Name -replace '\.ps1$','') + ".ps1"
            $destFile = Join-Path $scriptDir $fn
            
            $c = $c -replace '(?i)function\s+([a-z0-9_-]+)', 'function global:$1'
            Set-Content -Path $destFile -Value $c -Encoding UTF8 -Force
        }
        
        . $destFile
        Write-Host "[+] Installed: $fn" -ForegroundColor Green
    }
}

# AUTO-LOADER FOR MODULAR SCRIPTS
$cDir = Join-Path (Split-Path $PROFILE) "CustomScripts"
if (Test-Path $cDir) {
    Get-ChildItem -Path $cDir -Filter '*.ps1' | ForEach-Object {
        Unblock-File -LiteralPath $_.FullName -ErrorAction Ignore 
        . $_.FullName
    }
}
# ==========================================
'@

if (-not (Test-Path $PROFILE)) { New-Item -Path $PROFILE -ItemType File -Force | Out-Null }
$profContent = Get-Content -LiteralPath $PROFILE -Raw -ErrorAction Ignore

# Clean up old/buggy versions to prevent duplicates
if ($profContent -match 'POWERSHELL CUSTOM SCRIPT MANAGER') {
    $profContent = $profContent -replace '(?s)# ==========================================.*?# ==========================================', ''
}
if ($profContent -match 'AUTO-LOADER FOR MODULAR SCRIPTS') {
    $profContent = $profContent -replace '(?s)# AUTO-LOADER FOR MODULAR SCRIPTS.*', ''
}

# Embed the unbreakable engine into the Profile
Set-Content -LiteralPath $PROFILE -Value ($profContent.Trim() + "`n" + $engineCode) -Encoding UTF8 -Force

# Load the new engine into the current session
. $PROFILE

# Remove the old buggy script if it exists
$buggyFile = Join-Path (Split-Path $PROFILE) "CustomScripts\Install-PSScript.ps1"
if (Test-Path $buggyFile) { Remove-Item -LiteralPath $buggyFile -Force }

# Install default tools
Install-PSScript "function inps { Install-PSScript @args }" -Name "Alias-inps"

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

Write-Host "`n[SUCCESS] Engine perfectly embedded! No more loading errors." -ForegroundColor Cyan