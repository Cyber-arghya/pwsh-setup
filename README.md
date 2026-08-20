# pwsh-setup
# PowerShell Setup Toolkit

A lightweight PowerShell toolkit with two focused entry points: a persistent custom-script manager and a class-based development-environment installer. The installer is modular, idempotent, and lets you choose exactly which tools to install.

## Development Environment CLI

Run `Setup-FullDevEnvironment.ps1` from an elevated PowerShell window. With no parameters it opens an interactive component menu:

```powershell
.\Setup-FullDevEnvironment.ps1
```

For repeatable or automated setup, select components directly:

```powershell
# Install Git and VS Code
.\Setup-FullDevEnvironment.ps1 -Action Install -Component Core

# Install language tooling and Docker
.\Setup-FullDevEnvironment.ps1 -Action Install -Component Languages,Containers

# Install every component except VS Code extensions
.\Setup-FullDevEnvironment.ps1 -Action Install -All -SkipExtensions

# Only show the current tool versions
.\Setup-FullDevEnvironment.ps1 -Action Verify
```

Available components are `Core`, `Native` (MSYS2 and GCC), `Languages`, `Containers`, and `Extensions`. The installer skips tools already detected and refreshes the current session PATH after installation.

---

## ⚡ Quick Installation

1. Download the `install.bat` file from this repository.
2. Double-click `install.bat`.
3. The script will automatically download the core engine, bypass execution policies, and set up your environment.
4. **Close the terminal and open a new PowerShell window** to start using the tools.

---

## 🛠️ Built-in Commands

### 1. `inps` (Install PowerShell Script)
The core alias used to instantly install and save any new function or script into your permanent global environment.

**Syntax:**
```powershell
inps "<raw_code_or_file_path>" -Name "<OptionalName>"


##  Examples 

# Install a raw function directly from the terminal
inps "function Say-Hello { Write-Host 'Hello World!' -ForegroundColor Yellow }" -Name "Hello"

# Install multi-line code using a Here-String
inps @'
function Get-MyUptime {
    $os = Get-WmiObject win32_operatingsystem$uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
    Write-Host "Uptime: $($uptime.Days) Days, $($uptime.Hours) Hours"
}
'@ -Name "UptimeTool"

# Install an existing .ps1 file
inps "C:\Path\To\YourScript.ps1"