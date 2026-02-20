#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Cyber Station - Professional software installer via WinGet
.DESCRIPTION
    Modern web UI to install software using Windows Package Manager (WinGet),
    with robust error handling and a professional design.
.NOTES
    Author: Cyber Station
    Version: 2.0
#>

# Configuration
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:LogFile = Join-Path $PSScriptRoot "install.log"

# --- FONCTIONS UTILITAIRES ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $logMessage
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "SUCCESS"){"Green"}else{"Cyan"})
}

function Test-WinGetInstalled {
    try {
        $wingetVersion = winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WinGet detected: $wingetVersion" "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "WinGet not found. Installation required." "ERROR"
        return $false
    }
    return $false
}

function Test-AdminRights {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "Administrator privileges required!" "ERROR"
        return $false
    }
    return $true
}

function Get-InstalledWinGetIds {
    <#
    .SYNOPSIS
        Get installed WinGet IDs (server-side cache)
    #>
    param(
        [int]$CacheTtlSeconds = 300
    )

    if ($Script:InstalledCache -and $Script:InstalledCacheTime) {
        $age = (Get-Date) - $Script:InstalledCacheTime
        if ($age.TotalSeconds -lt $CacheTtlSeconds) {
            return $Script:InstalledCache
        }
    }

    $installedIds = New-Object System.Collections.Generic.HashSet[string]

    try {
        # WinGet JSON output
        $raw = (& winget list --output json --accept-source-agreements 2>$null) -join "`n"
        # Some versions print a header line before the JSON output
        $startIdx = $raw.IndexOf('{')
        $startIdxArr = $raw.IndexOf('[')
        if ($startIdx -lt 0 -or ($startIdxArr -ge 0 -and $startIdxArr -lt $startIdx)) { $startIdx = $startIdxArr }
        $jsonText = if ($startIdx -ge 0) { $raw.Substring($startIdx) } else { $raw }
        if (-not [string]::IsNullOrWhiteSpace($jsonText)) {
            $data = $jsonText | ConvertFrom-Json -ErrorAction Stop

            # Selon versions: .Sources[].Packages[] ou .Packages[]
            $pkgs = @()
            if ($null -ne $data.Sources) {
                foreach ($s in $data.Sources) {
                    if ($s.Packages) { $pkgs += $s.Packages }
                }
            } elseif ($data.Packages) {
                $pkgs = $data.Packages
            }

            foreach ($p in $pkgs) {
                $id = $p.PackageIdentifier
                if (-not [string]::IsNullOrWhiteSpace($id)) { [void]$installedIds.Add($id) }
            }
        }
    } catch {
        # Do not block the UI if JSON is not available
        Write-Log "Unable to read WinGet list as JSON: $($_.Exception.Message)" "WARNING"
    }

    $Script:InstalledCache = $installedIds
    $Script:InstalledCacheTime = Get-Date
    return $installedIds
}

function Install-WinGetApp {
    param(
        [string]$AppId,
        [string]$AppName
    )
    
    try {
        Write-Log "Starting install: $AppName ($AppId)"
        
        # Check if already installed
        $checkProcess = Start-Process -FilePath "winget" -ArgumentList "list", "--id", "`"$AppId`"", "--exact" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\winget_check.txt" -RedirectStandardError "$env:TEMP\winget_check_err.txt"
        
        if ($checkProcess.ExitCode -eq 0) {
            $checkOutput = Get-Content "$env:TEMP\winget_check.txt" -ErrorAction SilentlyContinue
            if ($checkOutput -and ($checkOutput -match $AppId -or $checkOutput -match $AppName)) {
                Write-Log "$AppName is already installed" "INFO"
                return @{Success=$true; Message="Already installed"}
            }
        }
        
        # Install
        Write-Log "Launching WinGet install..." "INFO"
        $installProcess = Start-Process -FilePath "winget" -ArgumentList "install", "--id", "`"$AppId`"", "--exact", "--accept-package-agreements", "--accept-source-agreements", "--silent", "--disable-interactivity" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\winget_install.txt" -RedirectStandardError "$env:TEMP\winget_install_err.txt"
        
        $installOutput = Get-Content "$env:TEMP\winget_install.txt" -ErrorAction SilentlyContinue | Out-String
        $installError = Get-Content "$env:TEMP\winget_install_err.txt" -ErrorAction SilentlyContinue | Out-String
        
        if ($installProcess.ExitCode -eq 0) {
            Write-Log "Install succeeded: $AppName" "SUCCESS"
            return @{Success=$true; Message="Install succeeded"}
        } 
        elseif ($installProcess.ExitCode -eq -1978335189) {
            # WinGet "already installed" exit code on some versions
            Write-Log "$AppName is already installed (detected during install)" "INFO"
            return @{Success=$true; Message="Already installed"}
        }
        else {
            $errorMsg = if ($installError) { $installError.Trim() } else { "Exit code: $($installProcess.ExitCode)" }
            Write-Log "Install failed: $AppName - $errorMsg" "ERROR"
            return @{Success=$false; Message="Failed: $errorMsg"}
        }
    } 
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Install error for ${AppName}: $errorMessage" "ERROR"
        return @{Success=$false; Message="Error: $errorMessage"}
    }
    finally {
        # Cleanup temp files
        Remove-Item "$env:TEMP\winget_*.txt" -ErrorAction SilentlyContinue
    }
}

# --- PRECHECKS ---
Write-Log "=== Cyber Station startup ===" "INFO"

if (-not (Test-AdminRights)) {
    Write-Host "ERROR: This script requires administrator privileges." -ForegroundColor Red
    Write-Host "Re-run PowerShell as Administrator." -ForegroundColor Yellow
    pause
    exit 1
}

if (-not (Test-WinGetInstalled)) {
    Write-Host "ERROR: WinGet is not installed." -ForegroundColor Red
    Write-Host "Install WinGet from: https://aka.ms/getwinget" -ForegroundColor Yellow
    pause
    exit 1
}

# --- SOFTWARE CATALOG ---
$Apps = @(
    # --- CYBER & ANALYSIS ---
    @{Id='PortSwigger.BurpSuite.Community'; Name='Burp Suite'; Cat='CYBER'; Desc='HTTP/Web interception proxy'}
    @{Id='SleuthKit.Autopsy'; Name='Autopsy'; Cat='CYBER'; Desc='Disk forensic analysis'}
    @{Id='ZAP.ZAP'; Name='OWASP ZAP'; Cat='CYBER'; Desc='Web vulnerability scanner'}
    @{Id='Insecure.Nmap'; Name='Nmap'; Cat='CYBER'; Desc='Network scanning and security'}
    @{Id='WiresharkFoundation.Wireshark'; Name='Wireshark'; Cat='CYBER'; Desc='Network protocol analyzer'}
    @{Id='KeePassXCTeam.KeePassXC'; Name='KeePassXC'; Cat='CYBER'; Desc='Offline password manager'}
    @{Id='DominikReichl.KeePass'; Name='KeePass 2'; Cat='CYBER'; Desc='Classic password manager'}
    @{Id='WinsiderSS.SystemInformer'; Name='System Informer'; Cat='CYBER'; Desc='Process Explorer alternative'}
    
    # --- DEV TOOLS ---
    @{Id='Anysphere.Cursor'; Name='Cursor AI'; Cat='DEV'; Desc='AI-powered code editor (VS Code fork)'}
    @{Id='Microsoft.VisualStudioCode'; Name='VS Code'; Cat='DEV'; Desc='Code editor'}
    @{Id='OpenJS.NodeJS.LTS'; Name='NodeJS'; Cat='DEV'; Desc='Runtime JavaScript Backend'}
    @{Id='Yarn.Yarn'; Name='Yarn'; Cat='DEV'; Desc='JavaScript package manager'}
    @{Id='pnpm.pnpm'; Name='pnpm'; Cat='DEV'; Desc='Fast package manager'}
    @{Id='Python.Python.3.12'; Name='Python 3'; Cat='DEV'; Desc='Python 3 interpreter'}
    @{Id='Python.Python.2.7'; Name='Python 2.7'; Cat='DEV'; Desc='Legacy Python 2.7'}
    @{Id='Git.Git'; Name='Git'; Cat='DEV'; Desc='Version control system'}
    @{Id='FireDaemon.OpenSSL'; Name='OpenSSL 3'; Cat='DEV'; Desc='SSL/TLS crypto toolkit'}
    @{Id='Notepad++.Notepad++'; Name='Notepad++'; Cat='DEV'; Desc='Advanced text editor'}
    @{Id='FileZilla.FileZilla'; Name='FileZilla'; Cat='DEV'; Desc='FTP/SFTP client'}
    @{Id='WinSCP.WinSCP'; Name='WinSCP'; Cat='DEV'; Desc='Secure file transfer client'}
    @{Id='PuTTY.PuTTY'; Name='PuTTY'; Cat='DEV'; Desc='SSH/Telnet client'}
    @{Id='WinMerge.WinMerge'; Name='WinMerge'; Cat='DEV'; Desc='File and folder diff tool'}

    # --- INFRA (RUNTIMES) ---
    @{Id='Microsoft.VCRedist.2015+.x64'; Name='VC++ 15-22 x64'; Cat='INFRA'; Desc='Modern C++ runtime'}
    @{Id='Microsoft.VCRedist.2013.x64'; Name='VC++ 2013 x64'; Cat='INFRA'; Desc='Legacy C++ runtime'}
    @{Id='Microsoft.DotNet.DesktopRuntime.8'; Name='.NET 8 Desktop'; Cat='INFRA'; Desc='Framework .NET 8 (LTS)'}
    @{Id='Microsoft.DotNet.DesktopRuntime.9'; Name='.NET 9 Desktop'; Cat='INFRA'; Desc='Framework .NET 9 Standard'}
    @{Id='Microsoft.DotNet.DesktopRuntime.10'; Name='.NET 10 Desktop'; Cat='INFRA'; Desc='Framework .NET 10 (2026)'}
    @{Id='Microsoft.DotNet.Framework.4.8.1'; Name='.NET 4.8.1'; Cat='INFRA'; Desc='Classic .NET Framework'}

    # --- JAVA STACK ---
    @{Id='EclipseAdoptium.Temurin.8.JDK'; Name='JDK 8 (Temurin)'; Cat='JAVA'; Desc='OpenJDK 8'}
    @{Id='EclipseAdoptium.Temurin.17.JDK'; Name='JDK 17 (Temurin)'; Cat='JAVA'; Desc='OpenJDK 17 LTS'}
    @{Id='EclipseAdoptium.Temurin.21.JDK'; Name='JDK 21 (Temurin)'; Cat='JAVA'; Desc='OpenJDK 21 LTS'}
    @{Id='Amazon.Corretto.11'; Name='JDK 11 (Corretto)'; Cat='JAVA'; Desc='Amazon Java 11'}
    @{Id='Amazon.Corretto.17'; Name='JDK 17 (Corretto)'; Cat='JAVA'; Desc='Amazon Java 17'}

    # --- DEVOPS ---
    @{Id='Docker.DockerDesktop'; Name='Docker'; Cat='DEVOPS'; Desc='Containers and virtualization'}
    @{Id='Hashicorp.Vagrant'; Name='Vagrant'; Cat='DEVOPS'; Desc='Dev environments management'}
    @{Id='Hashicorp.Terraform'; Name='Terraform'; Cat='DEVOPS'; Desc='Infrastructure as Code'}
    @{Id='Postman.Postman'; Name='Postman'; Cat='DEVOPS'; Desc='API testing and debugging'}
    
    # --- ADMIN & SYSTEM ---
    @{Id='Microsoft.Sysinternals.Suite'; Name='Sysinternals'; Cat='ADMIN'; Desc='Microsoft admin tools suite'}
    @{Id='Mobatek.MobaXterm'; Name='MobaXterm'; Cat='ADMIN'; Desc='Advanced terminal for Windows'}
    @{Id='voidtools.Everything'; Name='Everything'; Cat='ADMIN'; Desc='Instant file search'}
    @{Id='Microsoft.PowerToys'; Name='PowerToys'; Cat='ADMIN'; Desc='Windows power utilities'}
    @{Id='BleachBit.BleachBit'; Name='BleachBit'; Cat='ADMIN'; Desc='Open-source cleaner'}
    @{Id='CrystalDewWorld.CrystalDiskInfo'; Name='DiskInfo'; Cat='ADMIN'; Desc='Disk health monitoring'}
    @{Id='CPUID.CPU-Z'; Name='CPU-Z'; Cat='ADMIN'; Desc='Hardware information'}
    @{Id='AntibodySoftware.WizTree'; Name='WizTree'; Cat='ADMIN'; Desc='Disk space analyzer'}

    # --- UTILS & SECURITY ---
    @{Id='AnyDeskSoftwareGmbH.AnyDesk'; Name='AnyDesk'; Cat='UTIL'; Desc='Remote Desktop'}
    @{Id='Piriform.CCleaner'; Name='CCleaner'; Cat='UTIL'; Desc='System cleaning'}
    @{Id='Malwarebytes.Malwarebytes'; Name='Malwarebytes'; Cat='SEC'; Desc='Malware scanner'}
    @{Id='SaferNetworking.Spybot.SpywareRemover'; Name='Spybot 2'; Cat='SEC'; Desc='Anti-Spyware'}
    @{Id='Open-Shell.Open-Shell-Menu'; Name='Open-Shell'; Cat='UTIL'; Desc='Classic Start menu'}
    @{Id='Brave.Brave'; Name='Brave'; Cat='WEB'; Desc='Privacy-focused browser'}

    # --- STORAGE & SHARE ---
    @{Id='7zip.7zip'; Name='7-Zip'; Cat='SYS'; Desc='Compression'}
    @{Id='RARLab.WinRAR'; Name='WinRAR'; Cat='SYS'; Desc='Format RAR'}
    @{Id='Google.GoogleDrive'; Name='Google Drive'; Cat='CLOUD'; Desc='Cloud Storage'}
    @{Id='qBittorrent.qBittorrent'; Name='qBittorrent'; Cat='SHARE'; Desc='Torrent client'}

    # --- MESSAGING & DOCS ---
    @{Id='Discord.Discord'; Name='Discord'; Cat='MSG'; Desc='Chat and voice'}
    @{Id='Microsoft.Teams'; Name='Teams'; Cat='MSG'; Desc='Team collaboration'}
    @{Id='Foxit.FoxitReader'; Name='Foxit Reader'; Cat='DOCS'; Desc='PDF reader'}
    @{Id='LibreOffice.LibreOffice'; Name='LibreOffice'; Cat='DOCS'; Desc='Office suite'}

    # --- MULTIMEDIA ---
    @{Id='Krita.Krita'; Name='Krita'; Cat='IMAGE'; Desc='Digital painting'}
    @{Id='GIMP.GIMP'; Name='GIMP'; Cat='IMAGE'; Desc='Image editor'}
    @{Id='VideoLAN.VLC'; Name='VLC'; Cat='MEDIA'; Desc='Media player'}
    @{Id='Valve.Steam'; Name='Steam'; Cat='GAME'; Desc='PC games platform'}
)

$AppsJson = $Apps | ConvertTo-Json -Compress

# Use a single-quoted here-string so PowerShell does not interpret JS backticks (`).
$HtmlTemplate = @'
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='utf-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>Cyber Station - Professional Installer</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        
        :root {
            --primary: #0078d7;
            --primary-dark: #005a9e;
            --success: #107c10;
            --danger: #d13438;
            --warning: #ffaa44;
            --bg-main: #f5f5f5;
            --bg-card: #ffffff;
            --text-primary: #1f1f1f;
            --text-secondary: #666;
            --border: #e1e1e1;
            --shadow: 0 2px 8px rgba(0,0,0,0.1);
            --shadow-hover: 0 4px 16px rgba(0,0,0,0.15);
        }
        
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, 'Roboto', sans-serif;
            color: var(--text-primary);
            min-height: 100vh;
            padding: 20px;
            font-size: 14px;
        }
        
        .container {
            max-width: 1500px;
            margin: 0 auto;
            background: var(--bg-card);
            border-radius: 16px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        
        .layout {
            display: grid;
            grid-template-columns: 280px 1fr;
            min-height: calc(100vh - 40px);
        }

        .sidebar {
            background: linear-gradient(180deg, #0b1220 0%, #0e1a33 100%);
            color: rgba(255,255,255,0.92);
            padding: 18px 14px;
            border-right: 1px solid rgba(255,255,255,0.06);
        }

        .brand {
            padding: 10px 10px 16px 10px;
            border-bottom: 1px solid rgba(255,255,255,0.08);
            margin-bottom: 14px;
        }

        .brand-title {
            font-size: 16px;
            font-weight: 900;
            letter-spacing: 0.4px;
        }

        .brand-sub {
            margin-top: 6px;
            font-size: 12px;
            opacity: 0.8;
        }

        .side-section-title {
            margin: 14px 10px 8px 10px;
            font-size: 11px;
            font-weight: 800;
            letter-spacing: 0.9px;
            opacity: 0.75;
            text-transform: uppercase;
        }

        .side-search input {
            width: 100%;
            padding: 10px 12px;
            border: 1px solid rgba(255,255,255,0.14);
            background: rgba(255,255,255,0.06);
            border-radius: 10px;
            color: rgba(255,255,255,0.92);
            outline: none;
        }

        .side-search input::placeholder {
            color: rgba(255,255,255,0.55);
        }

        .nav-list {
            margin-top: 10px;
            display: flex;
            flex-direction: column;
            gap: 8px;
            max-height: calc(100vh - 260px);
            overflow: auto;
            padding-right: 6px;
        }

        .nav-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            padding: 10px 10px;
            border-radius: 12px;
            cursor: pointer;
            border: 1px solid rgba(255,255,255,0.08);
            background: rgba(255,255,255,0.04);
            transition: transform 0.15s, background 0.15s, border-color 0.15s;
            user-select: none;
        }

        .nav-item:hover {
            transform: translateY(-1px);
            border-color: rgba(255,255,255,0.16);
            background: rgba(255,255,255,0.07);
        }

        .nav-item.active {
            background: rgba(0,120,215,0.22);
            border-color: rgba(0,120,215,0.35);
        }

        .nav-left {
            display: flex;
            flex-direction: column;
            gap: 2px;
            min-width: 0;
        }

        .nav-name {
            font-weight: 800;
            font-size: 12px;
            letter-spacing: 0.3px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .nav-meta {
            font-size: 11px;
            opacity: 0.75;
        }

        .nav-badge {
            font-size: 11px;
            font-weight: 900;
            padding: 4px 10px;
            border-radius: 999px;
            background: rgba(255,255,255,0.12);
            border: 1px solid rgba(255,255,255,0.18);
        }

        .main {
            display: flex;
            flex-direction: column;
            min-width: 0;
        }

        .header {
            background: linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%);
            color: white;
            padding: 30px;
            text-align: center;
            box-shadow: var(--shadow);
        }
        
        .header h1 {
            font-size: 2.1em;
            font-weight: 600;
            margin-bottom: 10px;
            text-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        
        .header p {
            opacity: 0.9;
            font-size: 1.1em;
        }
        
        .topbar {
            padding: 18px 22px;
            background: var(--bg-main);
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 14px;
        }

        .topbar-left {
            display: flex;
            flex-direction: column;
            gap: 4px;
            min-width: 0;
        }

        .topbar-title {
            font-weight: 900;
            font-size: 14px;
            letter-spacing: 0.2px;
        }

        .topbar-sub {
            font-size: 12px;
            color: var(--text-secondary);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .topbar-actions {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }

        .chip {
            padding: 8px 12px;
            border: 1px solid var(--border);
            border-radius: 999px;
            background: white;
            font-weight: 800;
            font-size: 12px;
        }
        
        /* removed: old top filter buttons (now in sidebar) */
        
        .kpi-grid {
            padding: 18px 22px;
            background: var(--bg-main);
            border-bottom: 1px solid var(--border);
            display: grid;
            grid-template-columns: repeat(4, minmax(0, 1fr));
            gap: 14px;
        }

        .kpi-card {
            background: white;
            border: 1px solid var(--border);
            border-radius: 14px;
            padding: 14px 14px;
            box-shadow: 0 1px 0 rgba(0,0,0,0.04);
        }

        .kpi-label {
            font-size: 11px;
            font-weight: 900;
            letter-spacing: 0.8px;
            text-transform: uppercase;
            color: var(--text-secondary);
        }

        .kpi-value {
            margin-top: 8px;
            font-size: 22px;
            font-weight: 1000;
            letter-spacing: 0.2px;
            color: var(--text-primary);
        }

        .kpi-hint {
            margin-top: 6px;
            font-size: 12px;
            color: var(--text-secondary);
        }
        
        .main-content {
            padding: 22px;
            max-height: calc(100vh - 400px);
            overflow-y: auto;
        }
        
        .main-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 25px;
        }
        
        .category-box {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 20px;
            transition: all 0.3s;
            box-shadow: var(--shadow);
        }
        
        .category-box:hover {
            box-shadow: var(--shadow-hover);
            transform: translateY(-2px);
        }
        
        .category-title {
            font-weight: 700;
            font-size: 1.05em;
            color: var(--primary);
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid var(--border);
            display: flex;
            align-items: center;
            gap: 8px;
        }
        /* removed category icon to avoid encoding issues */
        
        .app-item {
            display: flex;
            align-items: flex-start;
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.2s;
            border: 2px solid transparent;
        }
        
        .app-item:hover {
            background: #f0f7ff;
            border-color: var(--primary);
            transform: translateX(5px);
        }

        .app-item.installed {
            opacity: 0.55;
            filter: grayscale(1);
            background: #f6f6f6;
            border-color: var(--border);
            cursor: not-allowed;
            transform: none !important;
        }

        .app-item.installed:hover {
            background: #f6f6f6;
            border-color: var(--border);
        }
        
        .app-item input[type='checkbox'] {
            width: 20px;
            height: 20px;
            margin-right: 12px;
            margin-top: 2px;
            cursor: pointer;
            accent-color: var(--primary);
        }
        
        .app-item.installed input[type='checkbox'] {
            cursor: not-allowed;
        }

        .app-info {
            flex: 1;
        }
        
        .app-name {
            font-weight: 600;
            color: var(--text-primary);
            margin-bottom: 4px;
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 13px;
        }
        
        .app-desc {
            font-size: 0.85em;
            color: var(--text-secondary);
            line-height: 1.4;
        }

        .badge {
            font-size: 0.75em;
            font-weight: 700;
            padding: 3px 10px;
            border-radius: 999px;
            text-transform: uppercase;
            letter-spacing: 0.4px;
            border: 1px solid transparent;
            user-select: none;
        }

        .badge.installed {
            background: rgba(16, 124, 16, 0.12);
            color: #0f5e0f;
            border-color: rgba(16, 124, 16, 0.22);
        }
        
        .footer-bar {
            position: sticky;
            bottom: 0;
            background: linear-gradient(135deg, #1f1f1f 0%, #2d2d2d 100%);
            color: white;
            padding: 25px 30px;
            box-shadow: 0 -4px 16px rgba(0,0,0,0.2);
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 20px;
        }
        
        .footer-left {
            display: flex;
            align-items: center;
            gap: 20px;
        }
        
        .counter {
            font-size: 1.1em;
            font-weight: 600;
            padding: 10px 20px;
            background: rgba(255,255,255,0.1);
            border-radius: 8px;
        }
        
        .btn-install {
            background: linear-gradient(135deg, var(--success) 0%, #0e6b0e 100%);
            color: white;
            border: none;
            padding: 15px 40px;
            border-radius: 8px;
            font-weight: 700;
            font-size: 1.1em;
            cursor: pointer;
            transition: all 0.3s;
            box-shadow: 0 4px 12px rgba(16,124,16,0.3);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .btn-install:hover:not(:disabled) {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(16,124,16,0.4);
        }
        
        .btn-install:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .console {
            background: #1e1e1e;
            color: #00ff00;
            font-family: 'Consolas', 'Courier New', monospace;
            padding: 15px;
            height: 150px;
            overflow-y: auto;
            font-size: 0.85em;
            border-radius: 8px;
            border: 1px solid #333;
            line-height: 1.6;
        }
        
        .console::-webkit-scrollbar {
            width: 8px;
        }
        
        .console::-webkit-scrollbar-track {
            background: #2d2d2d;
        }
        
        .console::-webkit-scrollbar-thumb {
            background: #555;
            border-radius: 4px;
        }
        
        .console-line {
            margin-bottom: 4px;
            word-wrap: break-word;
        }
        
        .console-line.info { color: #00ff00; }
        .console-line.success { color: #00ffff; }
        .console-line.error { color: #ff4444; }
        .console-line.warning { color: #ffaa00; }
        
        .progress-container {
            width: 100%;
            margin-top: 15px;
        }
        
        .progress-bar {
            width: 100%;
            height: 8px;
            background: rgba(255,255,255,0.2);
            border-radius: 4px;
            overflow: hidden;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--success), #00ff88);
            width: 0%;
            transition: width 0.3s;
            border-radius: 4px;
        }
        
        .hidden { display: none !important; }
        
        @media (max-width: 768px) {
            .layout {
                grid-template-columns: 1fr;
            }
            .sidebar {
                display: none;
            }
            .main-grid {
                grid-template-columns: 1fr;
            }
            .header h1 {
                font-size: 1.8em;
            }
            .footer-bar {
                flex-direction: column;
                text-align: center;
            }
            .kpi-grid {
                grid-template-columns: repeat(2, minmax(0, 1fr));
            }
        }
        
        .loading {
            display: inline-block;
            width: 12px;
            height: 12px;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 0.8s linear infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        /* Modal */
        .modal-overlay {
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.55);
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px;
            z-index: 9999;
            backdrop-filter: blur(6px);
        }

        .modal {
            width: min(560px, 100%);
            background: #ffffff;
            border-radius: 14px;
            box-shadow: 0 18px 55px rgba(0,0,0,0.35);
            overflow: hidden;
            transform: translateY(6px);
            animation: modalIn 140ms ease-out forwards;
        }

        @keyframes modalIn {
            from { opacity: 0; transform: translateY(14px) scale(0.98); }
            to { opacity: 1; transform: translateY(0) scale(1); }
        }

        .modal-header {
            padding: 18px 20px;
            font-weight: 800;
            font-size: 1.15em;
            border-bottom: 1px solid var(--border);
            background: linear-gradient(135deg, #f7f9ff 0%, #ffffff 100%);
        }

        .modal-body {
            padding: 18px 20px;
            color: var(--text-secondary);
            line-height: 1.55;
            font-size: 0.98em;
            white-space: pre-wrap;
        }

        .modal-actions {
            padding: 16px 20px;
            display: flex;
            justify-content: flex-end;
            gap: 10px;
            border-top: 1px solid var(--border);
            background: #fbfbfb;
        }

        .btn {
            border: 0;
            padding: 10px 16px;
            border-radius: 10px;
            cursor: pointer;
            font-weight: 700;
            transition: transform 0.15s, box-shadow 0.15s, opacity 0.15s;
        }

        .btn:active { transform: translateY(1px); }

        .btn-secondary {
            background: #e9eef8;
            color: #1f1f1f;
        }

        .btn-secondary:hover { box-shadow: 0 6px 18px rgba(0,0,0,0.10); }

        .btn-primary {
            background: linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%);
            color: white;
            box-shadow: 0 10px 22px rgba(0,120,215,0.25);
        }

        .btn-primary:hover { box-shadow: 0 12px 28px rgba(0,120,215,0.32); }
    </style>
</head>
<body>
    <div class='container'>
        <div class='layout'>
            <aside class='sidebar'>
                <div class='brand'>
                    <div class='brand-title'>CYBER STATION</div>
                    <div class='brand-sub'>WinGet dashboard installer</div>
                </div>

                <div class='side-section-title'>Search</div>
                <div class='side-search'>
                    <input type='text' id='searchInput' placeholder='Search apps...' autocomplete='off'>
                </div>

                <div class='side-section-title'>Categories</div>
                <div class='nav-list' id='categoryList'></div>
            </aside>

            <main class='main'>
                <div class='header'>
                    <h1>Cyber Station</h1>
                    <p>Professional Software Installer</p>
                </div>

                <div class='topbar'>
                    <div class='topbar-left'>
                        <div class='topbar-title'>Software Catalog</div>
                        <div class='topbar-sub' id='viewHint'>All apps</div>
                    </div>
                    <div class='topbar-actions'>
                        <div class='chip' id='chipInstalled'>Installed: 0</div>
                        <div class='chip' id='chipSelected'>Selected: 0</div>
                    </div>
                </div>

                <div class='kpi-grid'>
                    <div class='kpi-card'>
                        <div class='kpi-label'>Total apps</div>
                        <div class='kpi-value' id='totalCount'>0</div>
                        <div class='kpi-hint'>Available in catalog</div>
                    </div>
                    <div class='kpi-card'>
                        <div class='kpi-label'>Installed</div>
                        <div class='kpi-value' id='installedCount'>0</div>
                        <div class='kpi-hint'>Detected via WinGet</div>
                    </div>
                    <div class='kpi-card'>
                        <div class='kpi-label'>Selected</div>
                        <div class='kpi-value' id='selectedCount'>0</div>
                        <div class='kpi-hint'>Ready to install</div>
                    </div>
                    <div class='kpi-card'>
                        <div class='kpi-label'>Categories</div>
                        <div class='kpi-value' id='categoryCount'>0</div>
                        <div class='kpi-hint'>Groups in sidebar</div>
                    </div>
                </div>

                <div class='main-content'>
                    <div class='main-grid' id='app-grid'></div>
                </div>

                <div class='footer-bar'>
                    <div class='footer-left'>
                        <div class='counter' id='counter'>0 app(s) selected</div>
                        <button class='btn-install' id='installBtn' onclick='runInstall()'>
                            Install selected
                        </button>
                    </div>
                    <div style='flex: 1; margin-left: 20px;'>
                        <div class='console' id='logs'>
                            <div class='console-line info'>Ready. Select apps to install.</div>
                        </div>
                        <div class='progress-container'>
                            <div class='progress-bar'>
                                <div class='progress-fill' id='progressFill'></div>
                            </div>
                        </div>
                    </div>
                </div>
            </main>
        </div>
    </div>

    <div class='modal-overlay hidden' id='modalOverlay' aria-hidden='true'>
        <div class='modal' role='dialog' aria-modal='true' aria-labelledby='modalTitle'>
            <div class='modal-header' id='modalTitle'>Title</div>
            <div class='modal-body' id='modalBody'>Body</div>
            <div class='modal-actions' id='modalActions'></div>
        </div>
    </div>

    <script>
        const apps = __APPS_JSON__;
        let filteredApps = apps;
        let activeFilter = 'ALL';
        let installedIds = new Set();
        
        const grid = document.getElementById('app-grid');
        const searchInput = document.getElementById('searchInput');
        const categoryList = document.getElementById('categoryList');
        const installBtn = document.getElementById('installBtn');
        const viewHint = document.getElementById('viewHint');
        const chipInstalled = document.getElementById('chipInstalled');
        const chipSelected = document.getElementById('chipSelected');
        const modalOverlay = document.getElementById('modalOverlay');
        const modalTitle = document.getElementById('modalTitle');
        const modalBody = document.getElementById('modalBody');
        const modalActions = document.getElementById('modalActions');
        
        function openModal({ title, body, buttons }) {
            modalTitle.textContent = title || '';
            modalBody.textContent = body || '';
            modalActions.innerHTML = '';

            return new Promise(resolve => {
                (buttons || [{ text: 'OK', value: true, cls: 'btn-primary' }]).forEach(b => {
                    const btn = document.createElement('button');
                    btn.className = 'btn ' + (b.cls || 'btn-primary');
                    btn.textContent = b.text;
                    btn.onclick = () => {
                        closeModal();
                        resolve(b.value);
                    };
                    modalActions.appendChild(btn);
                });

                modalOverlay.classList.remove('hidden');
                modalOverlay.setAttribute('aria-hidden', 'false');
            });
        }

        function closeModal() {
            modalOverlay.classList.add('hidden');
            modalOverlay.setAttribute('aria-hidden', 'true');
        }

        modalOverlay.addEventListener('click', (e) => {
            if (e.target === modalOverlay) closeModal();
        });

        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !modalOverlay.classList.contains('hidden')) closeModal();
        });
        
        // Init
        const categories = [...new Set(apps.map(a => a.Cat))].sort();
        document.getElementById('totalCount').textContent = apps.length;
        document.getElementById('categoryCount').textContent = categories.length;

        const categoryLabels = {
            CYBER: 'Cyber Security',
            DEV: 'Developer Tools',
            DEVOPS: 'DevOps',
            INFRA: 'Infrastructure',
            JAVA: 'Java',
            ADMIN: 'Admin & System',
            UTIL: 'Utilities',
            SEC: 'Security',
            WEB: 'Web',
            SYS: 'System',
            CLOUD: 'Cloud',
            SHARE: 'File Sharing',
            MSG: 'Messaging',
            DOCS: 'Documents',
            IMAGE: 'Imaging',
            MEDIA: 'Media',
            GAME: 'Gaming'
        };

        function catLabel(code) {
            return categoryLabels[code] || code;
        }

        function renderSidebar() {
            categoryList.innerHTML = '';

            const counts = {};
            apps.forEach(a => { counts[a.Cat] = (counts[a.Cat] || 0) + 1; });

            const items = [{ key: 'ALL', label: 'All apps', meta: 'Everything', count: apps.length }].concat(
                categories.map(c => ({ key: c, label: catLabel(c), meta: c, count: counts[c] || 0 }))
            );

            items.forEach(it => {
                const el = document.createElement('div');
                el.className = 'nav-item' + (it.key === 'ALL' ? ' active' : '');
                el.dataset.key = it.key;
                el.innerHTML = `
                    <div class="nav-left">
                        <div class="nav-name">${it.label}</div>
                        <div class="nav-meta">${it.meta}</div>
                    </div>
                    <div class="nav-badge">${it.count}</div>
                `;
                el.onclick = () => setFilter(it.key);
                categoryList.appendChild(el);
            });
        }

        renderSidebar();
        
        // Search
        searchInput.addEventListener('input', (e) => {
            const query = e.target.value.toLowerCase();
            filteredApps = apps.filter(app => 
                app.Name.toLowerCase().includes(query) || 
                app.Desc.toLowerCase().includes(query) ||
                app.Cat.toLowerCase().includes(query)
            );
            if (activeFilter !== 'ALL') {
                filteredApps = filteredApps.filter(a => a.Cat === activeFilter);
            }
            renderApps();
        });

        async function loadInstalled() {
            const logBox = document.getElementById('logs');
            try {
                logBox.innerHTML += '<div class="console-line info">Checking installed apps...</div>';
                logBox.scrollTop = logBox.scrollHeight;

                const resp = await fetch('/api/installed');
                const data = await resp.json();
                const ok = data && (data.success === true || data.Success === true);
                const ids = data.installedIds || data.InstalledIds;
                if (ok && Array.isArray(ids)) {
                    installedIds = new Set(ids);
                    logBox.innerHTML += '<div class="console-line success">Installed detected: ' + installedIds.size + '</div>';
                    document.getElementById('installedCount').textContent = installedIds.size;
                    chipInstalled.textContent = 'Installed: ' + installedIds.size;
                } else {
                    logBox.innerHTML += '<div class="console-line warning">Installed detection: unexpected response</div>';
                }
            } catch (e) {
                logBox.innerHTML += '<div class="console-line warning">Could not check installed apps (you can still install)</div>';
            }
            logBox.scrollTop = logBox.scrollHeight;
        }
        
        function setFilter(cat) {
            activeFilter = cat;
            document.querySelectorAll('.nav-item').forEach(it => {
                it.classList.toggle('active', it.dataset.key === cat);
            });
            viewHint.textContent = (cat === 'ALL') ? 'All apps' : ('Category: ' + catLabel(cat));
            
            const query = searchInput.value.toLowerCase();
            filteredApps = apps.filter(app => {
                const matchesSearch = app.Name.toLowerCase().includes(query) || 
                                    app.Desc.toLowerCase().includes(query) ||
                                    app.Cat.toLowerCase().includes(query);
                return cat === 'ALL' ? matchesSearch : (matchesSearch && app.Cat === cat);
            });
            renderApps();
        }
        
        function renderApps() {
            grid.innerHTML = '';
            const appsByCat = {};
            
            filteredApps.forEach(app => {
                if (!appsByCat[app.Cat]) appsByCat[app.Cat] = [];
                appsByCat[app.Cat].push(app);
            });
            
            Object.keys(appsByCat).sort().forEach(cat => {
                const box = document.createElement('div');
                box.className = 'category-box';
                box.innerHTML = '<div class="category-title">' + catLabel(cat) + '</div>';
                
                appsByCat[cat].forEach(app => {
                    const isInstalled = installedIds.has(app.Id);
                    const item = document.createElement('label');
                    item.className = 'app-item' + (isInstalled ? ' installed' : '');
                    item.innerHTML = `
                        <input type="checkbox" value="${app.Id}" data-name="${app.Name}" data-desc="${app.Desc}" ${isInstalled ? 'disabled' : ''}>
                        <div class="app-info">
                            <div class="app-name">
                                <span>${app.Name}</span>
                                ${isInstalled ? '<span class="badge installed">Installed</span>' : ''}
                            </div>
                            <div class="app-desc">${app.Desc}</div>
                        </div>
                    `;
                    const cb = item.querySelector('input');
                    cb.onchange = updateCount;

                    if (isInstalled) {
                        item.addEventListener('click', (e) => {
                            e.preventDefault();
                            openModal({
                                title: 'Already installed',
                                body: app.Name + ' is already installed on this PC.',
                                buttons: [{ text: 'OK', value: true, cls: 'btn-primary' }]
                            });
                        });
                    }
                    box.appendChild(item);
                });
                grid.appendChild(box);
            });
            
            updateCount();
        }
        
        function updateCount() {
            const n = document.querySelectorAll('input:checked').length;
            document.getElementById('counter').textContent = n + ' app(s) selected';
            document.getElementById('selectedCount').textContent = n;
            chipSelected.textContent = 'Selected: ' + n;
        }
        
        async function runInstall() {
            const selected = Array.from(document.querySelectorAll('input:checked'));
            if (selected.length === 0) {
                await openModal({
                    title: 'Nothing selected',
                    body: 'Please select at least one app.',
                    buttons: [{ text: 'OK', value: true, cls: 'btn-primary' }]
                });
                return;
            }

            const appNames = selected.map(x => x.dataset.name).join('\n');
            const confirmed = await openModal({
                title: 'Confirm installation',
                body: 'You are about to install ' + selected.length + ' app(s):\n\n' + appNames + '\n\nDo you want to continue?',
                buttons: [
                    { text: 'Cancel', value: false, cls: 'btn-secondary' },
                    { text: 'Install', value: true, cls: 'btn-primary' }
                ]
            });
            if (!confirmed) return;
            
            installBtn.disabled = true;
            installBtn.innerHTML = '<span class="loading"></span> Installing...';
            
            const logBox = document.getElementById('logs');
            const progressFill = document.getElementById('progressFill');
            logBox.innerHTML = '';
            
            const total = selected.length;
            let success = 0;
            let failed = 0;
            
            logBox.innerHTML += '<div class="console-line info">Starting installation of ' + total + ' app(s)...</div>';
            
            for (let i = 0; i < selected.length; i++) {
                const cb = selected[i];
                const appName = cb.dataset.name;
                const progress = ((i + 1) / total) * 100;
                
                logBox.innerHTML += '<div class="console-line info">[' + (i + 1) + '/' + total + '] Installing ' + appName + '...</div>';
                logBox.scrollTop = logBox.scrollHeight;
                progressFill.style.width = progress + '%';
                
                try {
                    const resp = await fetch('/api/install?id=' + encodeURIComponent(cb.value) + '&name=' + encodeURIComponent(appName));
                    const result = await resp.json();
                    
                    const ok = (result && (result.success === true || result.Success === true));
                    const msg = (result && (result.message || result.Message)) || '';
                    if (ok) {
                        logBox.innerHTML += '<div class="console-line success">OK ' + appName + ' : ' + msg + '</div>';
                        success++;
                    } else {
                        logBox.innerHTML += '<div class="console-line error">FAIL ' + appName + ' : ' + msg + '</div>';
                        failed++;
                    }
                } catch (error) {
                    logBox.innerHTML += '<div class="console-line error">FAIL ' + appName + ' : ' + error.message + '</div>';
                    failed++;
                }
                
                logBox.scrollTop = logBox.scrollHeight;
            }
            
            progressFill.style.width = '100%';
            
            if (failed === 0) {
                logBox.innerHTML += '<div class="console-line success">Done. Success: ' + success + '/' + total + '</div>';
            } else {
                logBox.innerHTML += '<div class="console-line warning">Done. Success: ' + success + ', Failed: ' + failed + '</div>';
            }
            
            installBtn.disabled = false;
            installBtn.innerHTML = 'Install selected';
        }
        
        // Rendu initial
        (async () => {
            await loadInstalled();
            renderApps();
        })();
    </script>
</body>
</html>
'@

$HtmlContent = $HtmlTemplate.Replace('__APPS_JSON__', $AppsJson)

# --- SERVEUR BACKEND ---
function Start-WebServer {
    $url = "http://localhost:9090/"
    $listener = New-Object System.Net.HttpListener
    
    try {
        $listener.Prefixes.Add($url)
        $listener.Start()
        Write-Log "Web server started on $url" "SUCCESS"

        # Ctrl+C handler (clean shutdown)
        $cancelHandler = [ConsoleCancelEventHandler]{
            param($sender, $e)
            try {
                $e.Cancel = $true
                Write-Log "Ctrl+C received - stopping server..." "INFO"
                if ($listener -and $listener.IsListening) { $listener.Stop() }
            } catch { }
        }
        [Console]::add_CancelKeyPress($cancelHandler)
        
        # Ouvrir le navigateur
        Start-Process $url
        Write-Log "Browser opened automatically" "INFO"
        
        Write-Host "`n" -NoNewline
        Write-Host "=" * 60 -ForegroundColor Cyan
        Write-Host "  Cyber Station - Server running" -ForegroundColor Green
        Write-Host "  URL: $url" -ForegroundColor Yellow
        Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
        Write-Host "=" * 60 -ForegroundColor Cyan
        Write-Host "`n" -NoNewline
        
        while ($listener.IsListening) {
            try {
                $context = $listener.GetContext()
                $request = $context.Request
                $response = $context.Response
                
                # CORS
                $response.AddHeader("Access-Control-Allow-Origin", "*")
                $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")
                
                if ($request.HttpMethod -eq "OPTIONS") {
                    $response.StatusCode = 200
                    $response.Close()
                    continue
                }
                
                $path = $request.Url.PathAndQuery
                
                if ($path -eq "/" -or $path -eq "/index.html") {
                    # Main page
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($HtmlContent)
                    $response.ContentType = "text/html; charset=utf-8"
                    $response.ContentEncoding = [System.Text.Encoding]::UTF8
                    $response.StatusCode = 200
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    Write-Log "Main page served" "INFO"
                }
                elseif ($path.StartsWith("/api/install")) {
                    # Install endpoint (API)
                    $appId = $request.QueryString["id"]
                    $appName = $request.QueryString["name"]
                    
                    if ([string]::IsNullOrWhiteSpace($appId)) {
                        $result = @{Success=$false; Message="Missing app id"} | ConvertTo-Json -Compress
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                        $response.ContentType = "application/json; charset=utf-8"
                        $response.ContentEncoding = [System.Text.Encoding]::UTF8
                        $response.StatusCode = 400
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        Write-Log "Bad request: missing app id" "ERROR"
                    } else {
                        Write-Log "Install request: $appName ($appId)" "INFO"
                        $installResult = Install-WinGetApp -AppId $appId -AppName $appName
                        
                        $result = @{
                            Success = $installResult.Success
                            Message = $installResult.Message
                            AppId = $appId
                            AppName = $appName
                        } | ConvertTo-Json -Compress
                        
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                        $response.ContentType = "application/json; charset=utf-8"
                        $response.ContentEncoding = [System.Text.Encoding]::UTF8
                        $response.StatusCode = if ($installResult.Success) { 200 } else { 500 }
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                }
                elseif ($path.StartsWith("/api/installed")) {
                    # Endpoint: installed IDs (intersected with our catalog)
                    $installed = Get-InstalledWinGetIds
                    $catalogIds = New-Object System.Collections.Generic.HashSet[string]
                    foreach ($a in $Apps) { [void]$catalogIds.Add($a.Id) }

                    $installedInCatalog = @()
                    foreach ($id in $installed) {
                        if ($catalogIds.Contains($id)) { $installedInCatalog += $id }
                    }

                    $result = @{
                        Success = $true
                        InstalledIds = $installedInCatalog
                    } | ConvertTo-Json -Compress

                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentEncoding = [System.Text.Encoding]::UTF8
                    $response.StatusCode = 200
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    Write-Log "Installed list served: $($installedInCatalog.Count)" "INFO"
                }
                elseif ($path -eq "/install" -or $path -eq "/installed") {
                    # Legacy paths: return 410 without noisy logs (some browsers/extensions probe these)
                    $response.StatusCode = 410
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes("410 - Gone")
                    $response.ContentEncoding = [System.Text.Encoding]::UTF8
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.Close()
                }
                else {
                    # 404
                    $response.StatusCode = 404
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes("404 - Not found")
                    $response.ContentEncoding = [System.Text.Encoding]::UTF8
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    Write-Log "404: $path" "WARNING"
                }
                
                $response.Close()
            }
            catch {
                Write-Log "Request handling error: $_" "ERROR"
                try {
                    $response.StatusCode = 500
                    $result = @{Success=$false; Message="Server error: $_"} | ConvertTo-Json -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentEncoding = [System.Text.Encoding]::UTF8
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.Close()
                } catch {
                    # Ignorer les erreurs de fermeture
                }
            }
        }
    }
    catch {
        Write-Log "Critical server error: $_" "ERROR"
        Write-Host "`nERROR: Unable to start the web server." -ForegroundColor Red
        Write-Host "Make sure the port 9090 is not already in use." -ForegroundColor Yellow
        pause
        exit 1
    }
    finally {
        try { [Console]::remove_CancelKeyPress($cancelHandler) } catch { }
        if ($listener.IsListening) {
            $listener.Stop()
            Write-Log "Server stopped" "INFO"
        }
    }
}

# Clean shutdown hook
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Log "Script exit detected" "INFO"
}

# Start server
try {
    Start-WebServer
}
catch {
    Write-Log "Fatal error: $_" "ERROR"
    Write-Host "`nA fatal error occurred. Check the log file: $Script:LogFile" -ForegroundColor Red
    pause
    exit 1
}
