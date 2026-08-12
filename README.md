# pwsh-setup
# PowerShell Custom Script Manager 🚀

A lightweight, persistent, and modular script manager for Windows PowerShell. This tool allows you to instantly inject, save, and globally execute custom PowerShell functions and scripts without worrying about scope, execution policies, or profile reloading.

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