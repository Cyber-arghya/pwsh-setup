# ==============================================================================
# Architecture: Core Strategy Contracts & Utilities
# ==============================================================================

class PathHelper {
    # Validates true directory ancestry with trailing separator boundaries
    static [bool] IsSubPathOf([string]$childPath, [string]$parentPath) {
        $parent = $parentPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $child  = $childPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        return $child.StartsWith($parent, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

class IOrganizationStrategy {
    [string] GetDestinationSubFolder([System.IO.FileInfo]$file) {
        throw [System.NotImplementedException]::new()
    }
}

# Organizes photos to 'Photos/Year/Month', all other files to extension-named folders
class HybridExtensionMediaStrategy : IOrganizationStrategy {
    [string[]]$PhotoExtensions = @('.jpg', '.jpeg', '.png', '.heic', '.raw', '.dng', '.webp')

    [string] GetDestinationSubFolder([System.IO.FileInfo]$file) {
        $ext = $file.Extension.ToLower()
        if ($this.PhotoExtensions -contains $ext) {
            $year = $file.LastWriteTime.ToString('yyyy')
            $month = $file.LastWriteTime.ToString('MM-MMMM')
            return [System.IO.Path]::Combine("Photos", $year, $month)
        }
        return $file.Extension.TrimStart('.').ToUpper()
    }
}

# Routes directly to destination root without subfolders
class DirectDestinationStrategy : IOrganizationStrategy {
    [string] GetDestinationSubFolder([System.IO.FileInfo]$file) {
        return ""
    }
}

# ==============================================================================
# Architecture: History & Rollback Stack
# ==============================================================================

class HistoryManager {
    [string]$LogPath

    HistoryManager([string]$basePath) {
        $this.LogPath = [System.IO.Path]::Combine($basePath, '.organize_history.json')
    }

    [void] SaveSession([array]$moves) {
        if ($moves.Count -eq 0) { return }

        $history = @()
        if ([System.IO.File]::Exists($this.LogPath)) {
            $history = @(Get-Content -Path $this.LogPath -Raw | ConvertFrom-Json)
        }

        $history += [PSCustomObject]@{
            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Moves     = $moves
        }

        $history | ConvertTo-Json -Depth 4 | Set-Content -Path $this.LogPath -Force
        (Get-Item -Path $this.LogPath -Force).Attributes = 'Hidden'
    }

    [bool] RollbackLastSession([bool]$whatIf) {
        if (-not [System.IO.File]::Exists($this.LogPath)) {
            Write-Warning "No history file found."
            return $false
        }

        $history = @(Get-Content -Path $this.LogPath -Raw | ConvertFrom-Json)
        if ($history.Count -eq 0) { return $false }

        $lastSession = $history[-1]

        foreach ($entry in $lastSession.Moves) {
            if ([System.IO.File]::Exists($entry.CurrentPath)) {
                $target = $this.GetSafePath($entry.OriginalPath)
                if ($whatIf) {
                    Write-Host "[WhatIf Undo] $($entry.CurrentPath) -> $target" -ForegroundColor Cyan
                } else {
                    Move-Item -Path $entry.CurrentPath -Destination $target -Force
                    $parent = [System.IO.Path]::GetDirectoryName($entry.CurrentPath)
                    if ((Get-ChildItem -Path $parent -Force | Measure-Object).Count -eq 0) {
                        Remove-Item -Path $parent -Force -Recurse
                    }
                }
            }
        }

        if (-not $whatIf) {
            # Prevent negative index duplicate array mutation bug when count is 1
            if ($history.Count -gt 1) {
                $remaining = @($history[0..($history.Count - 2)])
                $remaining | ConvertTo-Json -Depth 4 | Set-Content -Path $this.LogPath -Force
                (Get-Item -Path $this.LogPath -Force).Attributes = 'Hidden'
            } else {
                Remove-Item -Path $this.LogPath -Force
            }
        }
        return $true
    }

    [string] GetSafePath([string]$targetPath) {
        if (-not [System.IO.File]::Exists($targetPath)) { return $targetPath }
        $dir = [System.IO.Path]::GetDirectoryName($targetPath)
        $base = [System.IO.Path]::GetFileNameWithoutExtension($targetPath)
        $ext = [System.IO.Path]::GetExtension($targetPath)
        $i = 1
        while ([System.IO.File]::Exists([System.IO.Path]::Combine($dir, "$base ($i)$ext"))) { $i++ }
        return [System.IO.Path]::Combine($dir, "$base ($i)$ext")
    }
}

# ==============================================================================
# Architecture: Core Execution Engine
# ==============================================================================

class FileOrganizer {
    [string]$SourcePath
    [string]$DestinationPath
    [IOrganizationStrategy]$Strategy
    [HistoryManager]$History
    [string[]]$AllowedExtensions = @()
    [string[]]$IgnoredExtensions = @('.lnk', '.url', '.ini', '.sys', '.dll', '.bat', '.cmd', '.ps1', '.vbs', '.tmp', '.lock', '.log')
    [string[]]$IgnoredFiles = @('desktop.ini', 'thumbs.db', '.gitignore', '.env', '.organize_history.json', '.last_daily_run')
    [string[]]$BlockedSubFolders = @(
        'AppData', 'Application Data', 'Local Settings', 'Cookies', 
        'NetHood', 'PrintHood', 'Recent', 'SendTo', 'Start Menu', 
        'Templates', 'Windows', 'System Volume Information', '$Recycle.Bin', 'ProgramData'
    )
    [bool]$Recurse = $false
    [bool]$WhatIf = $false

    FileOrganizer([string]$source, [string]$destination, [IOrganizationStrategy]$strategy, [bool]$recurse, [bool]$whatIf) {
        $this.SourcePath = (Resolve-Path -Path $source).Path
        $this.DestinationPath = if ($destination) { (Resolve-Path -Path $destination).Path } else { $this.SourcePath }
        $this.Strategy = $strategy
        $this.History  = [HistoryManager]::new($this.SourcePath)
        $this.Recurse  = $recurse
        $this.WhatIf   = $whatIf
        $this.ValidatePath()
    }

    [void] ValidatePath() {
        $critical = @($env:SystemRoot, ${env:ProgramFiles}, ${env:ProgramFiles(x86)}, $env:UserProfile, $env:ProgramData, $env:SystemDrive) | 
            Where-Object { -not [string]::IsNullOrEmpty($_) } | 
            ForEach-Object { (Resolve-Path -Path $_ -ErrorAction SilentlyContinue).Path }

        $comparer = [System.StringComparer]::OrdinalIgnoreCase

        if ($this.SourcePath -match '^[a-zA-Z]:\\?$') {
            throw "Aborted: Root drive partition ($($this.SourcePath)) cannot be organized directly."
        }

        # Case-insensitive path validation for critical system root paths
        foreach ($critPath in $critical) {
            if ($comparer.Equals($this.SourcePath, $critPath)) {
                throw "Aborted: Critical system directory ($($this.SourcePath)) cannot be targeted."
            }
        }

        $dir = [System.IO.DirectoryInfo]::new($this.SourcePath)
        while ($dir) {
            if ([System.IO.Directory]::Exists([System.IO.Path]::Combine($dir.FullName, '.git'))) {
                throw "Aborted: Path is inside a Git repository ($($dir.FullName))."
            }
            $dir = $dir.Parent
        }
    }

    [bool] IsFileEligible([System.IO.FileInfo]$file) {
        $ext = $file.Extension.ToLower()
        $name = $file.Name.ToLower()

        if ([string]::IsNullOrEmpty($ext) -or 
            ($file.Attributes -band [System.IO.FileAttributes]::Hidden) -or 
            ($file.Attributes -band [System.IO.FileAttributes]::System) -or 
            ($this.IgnoredExtensions -contains $ext) -or 
            ($this.IgnoredFiles -contains $name)) {
            return $false
        }

        # Block access into protected subdirectories
        $relPath = $file.DirectoryName.Substring($this.SourcePath.Length).TrimStart('\', '/')
        if (-not [string]::IsNullOrEmpty($relPath)) {
            $segments = $relPath.Split([System.IO.Path]::DirectorySeparatorChar)
            foreach ($seg in $segments) {
                if ($this.BlockedSubFolders -contains $seg) {
                    return $false
                }
            }
        }

        # Sibling prefix safety: skip only if destination is a genuine subfolder of source
        if ([PathHelper]::IsSubPathOf($this.DestinationPath, $this.SourcePath) -and $this.DestinationPath -ne $this.SourcePath) {
            if ([PathHelper]::IsSubPathOf($file.FullName, $this.DestinationPath)) {
                return $false
            }
        }

        # Skip recursion loops for files already residing inside their target structure
        if ($this.Recurse) {
            $expectedSubFolder = $this.Strategy.GetDestinationSubFolder($file)
            if (-not [string]::IsNullOrEmpty($expectedSubFolder)) {
                $targetDir = [System.IO.Path]::Combine($this.DestinationPath, $expectedSubFolder)
                if ($file.DirectoryName -eq $targetDir -or [PathHelper]::IsSubPathOf($file.DirectoryName, $targetDir)) {
                    return $false
                }
            }
        }

        if ($this.AllowedExtensions.Count -gt 0 -and ($this.AllowedExtensions -notcontains $ext)) {
            return $false
        }

        try {
            # Shared ReadWrite avoids false positives on open file handles
            $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $stream.Close()
            $stream.Dispose()
            return $true
        } catch {
            return $false
        }
    }

    [void] Run() {
        $moves = @()
        $files = (Get-ChildItem -Path $this.SourcePath -File -Force -Recurse:$this.Recurse)

        foreach ($file in $files) {
            if (-not $this.IsFileEligible($file)) { 
                if ($this.WhatIf) { Write-Host "[WhatIf Skipped] $($file.FullName)" -ForegroundColor DarkGray }
                continue 
            }

            $subFolder = $this.Strategy.GetDestinationSubFolder($file)
            $destDir = if ($subFolder) { [System.IO.Path]::Combine($this.DestinationPath, $subFolder) } else { $this.DestinationPath }
            
            # Prevent redundant operations if file already exists in calculated destination
            if ($file.DirectoryName.TrimEnd('\', '/') -eq $destDir.TrimEnd('\', '/')) {
                continue
            }

            $destFile = $this.History.GetSafePath([System.IO.Path]::Combine($destDir, $file.Name))

            if ($this.WhatIf) {
                Write-Host "[WhatIf Move] $($file.FullName) -> $destFile" -ForegroundColor Yellow
                continue
            }

            if (-not [System.IO.Directory]::Exists($destDir)) {
                [System.IO.Directory]::CreateDirectory($destDir) | Out-Null
            }

            Move-Item -Path $file.FullName -Destination $destFile -Force
            $moves += [PSCustomObject]@{
                OriginalPath = $file.FullName
                CurrentPath  = $destFile
            }
        }

        if (-not $this.WhatIf) {
            $this.History.SaveSession($moves)
        }
    }

    [void] Undo() {
        if ($this.History.RollbackLastSession($this.WhatIf)) {
            if (-not $this.WhatIf) {
                Write-Host "Undo completed successfully." -ForegroundColor Green
            }
        }
    }
}

# ==============================================================================
# Architecture: Watch Manager (Fixed for PS5.1/PS7+ & Multi-Arg Parsing)
# ==============================================================================

class WatchManager {
    [string]$TaskPrefix = "OrganizeFiles_Watcher_"

    [string] GetPathHash([string]$path) {
        $cleanPath = $path.TrimEnd('\', '/').ToLower()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanPath)
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $hasher.ComputeHash($bytes)
        return [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 8)
    }

    [string] GetTaskName([string]$path) {
        return "$($this.TaskPrefix)$($this.GetPathHash($path))"
    }

    [void] RegisterWatch([string]$sourcePath, [string]$destPath, [string[]]$extensions, [bool]$recurse) {
        $taskName = $this.GetTaskName($sourcePath)
        
        # Dynamically detect active PowerShell engine path (pwsh.exe or powershell.exe)
        $psBinary = (Get-Process -Id $PID).Path

        # Properly format and quote array elements for CLI argument parsing
        $extArg = if ($extensions -and $extensions.Count -gt 0) { 
            "-t " + (($extensions | ForEach-Object { "'$($_)'" }) -join ', ') 
        } else { "" }

        $recArg = if ($recurse) { "-r" } else { "" }
        $destArg = if ($destPath) { "-d '$destPath'" } else { "" }

        $metaDescription = "OrganizeWatch|$sourcePath|Dest: $(if($destPath){$destPath}else{'SELF'})|Extensions: $(if($extArg){$extArg}else{'ALL'})|Recurse: $recurse"
        
        # Construct the script block command safely with single-quote boundaries
        $innerCommand = ". '$($PROFILE)'; Organize-Files -p '$sourcePath' $destArg $extArg $recArg"
        $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$innerCommand`""

        $action = New-ScheduledTaskAction -Execute $psBinary -Argument $arguments
        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerLogon, $triggerStartup) -Settings $settings -Description $metaDescription -Force | Out-Null
        
        $watchId = $this.GetPathHash($sourcePath)
        Write-Host "Watch registered: [ID: $watchId] $sourcePath -> $(if($destPath){$destPath}else{'Self'})" -ForegroundColor Green
    }

    [bool] UnregisterById([string]$watchId) {
        $fullTaskName = if ($watchId.StartsWith($this.TaskPrefix)) { $watchId } else { "$($this.TaskPrefix)$watchId" }
        $existing = Get-ScheduledTask -TaskName $fullTaskName -ErrorAction SilentlyContinue

        if ($existing) {
            $descParts = $existing.Description -split '\|'
            $path = if ($descParts.Count -gt 1) { $descParts[1] } else { "Path unknown" }
            
            Unregister-ScheduledTask -TaskName $fullTaskName -Confirm:$false
            Write-Host "Stopped watching [ID: $($fullTaskName.Replace($this.TaskPrefix, ''))] -> $path" -ForegroundColor Yellow
            return $true
        }
        return $false
    }

    [void] UnregisterByPath([string]$targetPath) {
        $taskName = $this.GetTaskName($targetPath)
        if (-not $this.UnregisterById($taskName)) {
            Write-Warning "No active watch task found for: $targetPath"
        }
    }

    [void] ListWatchedFolders() {
        $tasks = Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "$($this.TaskPrefix)*" }

        if (-not $tasks -or $tasks.Count -eq 0) {
            Write-Host "No folders are currently being watched." -ForegroundColor Yellow
            return
        }

        $list = @()
        foreach ($t in $tasks) {
            $descParts = $t.Description -split '\|'
            $source = if ($descParts.Count -gt 1) { $descParts[1] } else { "Unknown" }
            $dest   = if ($descParts.Count -gt 2) { $descParts[2].Replace('Dest: ', '') } else { "SELF" }
            $filter = if ($descParts.Count -gt 3) { $descParts[3].Replace('Extensions: ', '') } else { "ALL" }
            $rec    = if ($descParts.Count -gt 4) { $descParts[4].Replace('Recurse: ', '') } else { "False" }

            $list += [PSCustomObject]@{
                ID          = $t.TaskName.Replace($this.TaskPrefix, '')
                SourcePath  = $source
                Destination = $dest
                Filters     = $filter
                Recursive   = $rec
                State       = $t.State
            }
        }

        $list | Format-Table -AutoSize
    }
}
# ==============================================================================
# CLI Wrapper Function
# ==============================================================================

function Organize-Files {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Position = 0)]
        [Alias('p')]
        [string]$Path = (Get-Location).Path,

        [Alias('d')]
        [string]$Destination,

        [Alias('t')]
        [string[]]$TargetExtension,

        [Alias('u')]
        [switch]$Undo,

        [Alias('r')]
        [switch]$Recurse,

        [Alias('ls')]
        [switch]$ListExtensions,

        [Alias('w')]
        [switch]$Watch,

        [Alias('sw')]
        [switch]$StopWatch,

        [Alias('lw')]
        [switch]$ListWatch
    )

    $watcher = [WatchManager]::new()

    if ($ListWatch) {
        $watcher.ListWatchedFolders()
        return
    }

    if ($Path -match '^[A-Fa-f0-9]{8}$') {
        if ($watcher.UnregisterById($Path)) {
            return
        }
    }

    $resolvedSource = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue).Path
    if (-not $resolvedSource) {
        Write-Error "Invalid source path or Watch ID: $Path"
        return
    }

    $resolvedDest = $null
    if ($Destination) {
        if (-not (Test-Path -Path $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }
        $resolvedDest = (Resolve-Path -Path $Destination).Path
    }

    if ($Watch) {
        $watcher.RegisterWatch($resolvedSource, $resolvedDest, $TargetExtension, $Recurse.IsPresent)
        return
    }

    if ($StopWatch) {
        $watcher.UnregisterByPath($resolvedSource)
        return
    }

    if ($ListExtensions) {
        $ignored = @('.lnk', '.url', '.ini', '.sys', '.dll', '.bat', '.cmd', '.ps1', '.vbs', '.tmp', '.lock', '.log')
        $items = Get-ChildItem -Path $resolvedSource -File -Force -Recurse:$Recurse | 
            Where-Object { $_.Extension -and ($ignored -notcontains $_.Extension.ToLower()) } | 
            Group-Object { $_.Extension.TrimStart('.').ToLower() } | 
            Select-Object @{N='Extension';E={$_.Name}}, @{N='Count';E={$_.Count}} | 
            Sort-Object Count -Descending

        $items | Format-Table -AutoSize
        return
    }

    $dailyLog = [System.IO.Path]::Combine($resolvedSource, '.last_daily_run')
    $isTaskRun = [Environment]::CommandLine -match '-WindowStyle Hidden'

    if ($isTaskRun -and [System.IO.File]::Exists($dailyLog)) {
        $lastRun = [System.IO.File]::GetLastWriteTime($dailyLog).Date
        if ($lastRun -eq [DateTime]::Today) {
            return
        }
    }

    try {
        $strategy = [HybridExtensionMediaStrategy]::new()
        
        # Validated WhatIf evaluation covering preference and switch triggers
        $isWhatIf = [bool]($PSCmdlet.WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf'))
        $organizer = [FileOrganizer]::new($resolvedSource, $resolvedDest, $strategy, $Recurse.IsPresent, $isWhatIf)

        if ($Undo) {
            $organizer.Undo()
            return
        }

        if ($TargetExtension) {
            $organizer.AllowedExtensions = $TargetExtension | ForEach-Object {
                if ($_ -notlike '.*') { ".$_" } else { $_ }
            } | ForEach-Object { $_.ToLower() }
        }

        $organizer.Run()

        if (-not $isWhatIf) {
            Set-Content -Path $dailyLog -Value (Get-Date).ToString() -Force
            (Get-Item -Path $dailyLog -Force).Attributes = 'Hidden'
            Write-Host "Organization completed successfully." -ForegroundColor Green
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

# Dynamic Tab-Completer with active runspace context resolution
Register-ArgumentCompleter -CommandName 'Organize-Files' -ParameterName 'TargetExtension' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $targetPath = if ($fakeBoundParameters.ContainsKey('Path')) { 
        $fakeBoundParameters['Path'] 
    } elseif ($ExecutionContext.SessionState.Path.CurrentLocation) {
        $ExecutionContext.SessionState.Path.CurrentLocation.Path
    } else {
        [System.IO.Directory]::GetCurrentDirectory()
    }

    $resolvedPath = (Resolve-Path -Path $targetPath -ErrorAction SilentlyContinue).Path
    if (-not $resolvedPath -or -not (Test-Path -Path $resolvedPath)) { return @() }

    $ignored = @('.lnk', '.url', '.ini', '.sys', '.dll', '.bat', '.cmd', '.ps1', '.vbs', '.tmp', '.lock', '.log')
    Get-ChildItem -Path $resolvedPath -File -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Extension -and ($ignored -notcontains $_.Extension.ToLower()) } | 
        Select-Object -ExpandProperty Extension -Unique | 
        ForEach-Object { $_.TrimStart('.').ToLower() } | 
        Where-Object { $_ -like "$wordToComplete*" } | 
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# ==============================================================================
# AUTO-SETUP / PROFILE INJECTION (Run once to install permanently)
# ==============================================================================
$installDir = "$env:LOCALAPPDATA\FileOrganizer"
$installPath = "$installDir\organizer.ps1"

# Check if the script is being run from a location other than its permanent install path
if ($PSCommandPath -and $PSCommandPath -ne$installPath) {
    Write-Host "`n[*] Installing File Organizer to $installDir..." -ForegroundColor Yellow
    
    # 1. Create directory and copy the script permanently
    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Force -Path $installDir | Out-Null }
    Copy-Item -Path $PSCommandPath -Destination $installPath -Force

    # 2. Define profile paths for both PowerShell 5.1 and PowerShell 7+
    $profilesToInject = @(
        "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
        "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    )

    $injectLine = ". `"$installPath`""

    # 3. Inject into profiles
    foreach ($prof in $profilesToInject) {
        $profDir = Split-Path -Parent $prof
        if (-not (Test-Path $profDir)) { New-Item -ItemType Directory -Force -Path $profDir | Out-Null }
        if (-not (Test-Path $prof)) { New-Item -ItemType File -Force -Path $prof | Out-Null }

        $content = Get-Content $prof -Raw
        if ($null -eq $content) { $content = "" }

        # Add the line only if it doesn't already exist
        if ($content -notmatch \[regex\]::Escape($injectLine)) {
            $content = $content.TrimEnd() + "`n`n# File Organizer Permanent Setup`n$injectLine`n"
            Set-Content -Path $prof -Value $content
            Write-Host "[+] Successfully injected into: $prof" -ForegroundColor Green
        } else {
            Write-Host "[!] Already installed in: $prof" -ForegroundColor DarkGray
        }
    }
    
    Write-Host "[*] Setup Complete! Restart your terminal or run '. `$PROFILE' to start using 'Organize-Files'." -ForegroundColor Cyan
}
