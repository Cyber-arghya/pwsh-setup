# ==========================================
# File: setup.ps1
# Description: Installs a modular script manager and essential aliases
# ==========================================

$bootstrapCode = @'
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
            
            # AUTOMAGIC: Enforce global scope for raw functions to survive installation
            $c = $c -replace '(?i)function\s+([a-z0-9_-]+)', 'function global:$1'
            Set-Content -Path $destFile -Value $c -Encoding UTF8 -Force
        }

        if (-not (Test-Path $PROFILE)) { New-Item -Path $PROFILE -ItemType File -Force | Out-Null }
        
        # ROBUST AUTO-LOADER (Fixes MotW / Execution Policy blocks on reboot)
        $loaderScript = @"
`n# AUTO-LOADER FOR MODULAR SCRIPTS (PERMANENT FIX)
if (Test-Path `"$scriptDir`") {
    Get-ChildItem -Path `"$scriptDir`" -Filter '*.ps1' | ForEach-Object {
        Unblock-File -LiteralPath `$_.FullName -ErrorAction Ignore 
        . `$_.FullName
    }
}
"@
        $profContent = Get-Content -LiteralPath $PROFILE -Raw -ErrorAction Ignore
        if ($profContent -notmatch 'AUTO-LOADER FOR MODULAR SCRIPTS') {
            Add-Content -Path $PROFILE -Value $loaderScript -Encoding UTF8
        } elseif ($profContent -match 'AUTO-LOADER FOR MODULAR SCRIPTS' -and $profContent -notmatch 'Unblock-File') {
             # Upgrade old loader to robust loader
             $profContent = $profContent -replace '(?s)# AUTO-LOADER FOR MODULAR SCRIPTS.*', ''
             Set-Content -LiteralPath $PROFILE -Value ($profContent + $loaderScript) -Encoding UTF8 -Force
        }
        
        . $destFile
        Write-Host "[+] Installed: $fn" -ForegroundColor Green
    }
}
'@

# 1. Enforce Execution Policy for the Current User
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 2. Bootstrap the core engine
Invoke-Expression $bootstrapCode
Install-PSScript $bootstrapCode -Name "Install-PSScript"

# 3. Setup Essential Shortcuts & Functions
Install-PSScript "function inps { Install-PSScript @args }" -Name "Alias-inps"

inps @'
function ip {
    Write-Host "[ Public IP ]" -ForegroundColor Cyan
    try { 
        $pub = (Invoke-RestMethod ifconfig.me/ip -TimeoutSec 3).Trim()
        Write-Host $pub -ForegroundColor Green 
    } 
    catch { 
        Write-Host "Offline / Unreachable" -ForegroundColor Red 
    }
    
    Write-Host "`n[ Local & Virtual IPs ]" -ForegroundColor Cyan
    Get-NetIPAddress -AddressFamily IPv4 | 
        Where-Object { $_.IPAddress -ne '127.0.0.1' } | 
        Sort-Object InterfaceAlias |
        Select-Object @{Name="Adapter Name";Expression={$_.InterfaceAlias}}, 
                      @{Name="IP Address";Expression={$_.IPAddress}} | 
        Format-Table -AutoSize
}
'@ -Name "Alias-ip"

# 4. Final Reload
. $PROFILE
Write-Host "`n[SUCCESS] PowerShell Custom Script Manager installed globally!" -ForegroundColor Cyan