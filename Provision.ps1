[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$ReportPath = Join-Path $PSScriptRoot "Inventory_Dashboard.html"

# --- HELPER: Professional Header ---
function Show-Header {
    Clear-Host
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "    DYNAMIC WINGET PROVISIONING ENGINE (2026)       " -ForegroundColor White
    Write-Host "=====================================================" -ForegroundColor Cyan
}

# --- 1. ANALYTICAL SCAN ---
Show-Header
Write-Host "[*] Extracting system metadata..." -ForegroundColor Gray

# Fetching winget list. Skipping headers for clean parsing.
$RawApps = winget list --accept-source-agreements | Select-Object -Skip 2
$GlobalInstalled = @()
$Counter = 1

foreach ($line in $RawApps) {
    # Improved Regex for clean column separation
    if ($line -match '^(.*?)\s{2,}(.*?)\s{2,}(.*?)\s{2,}(.*)$') {
        $Name    = $Matches[1].Trim()
        $PkgID   = $Matches[2].Trim()
        $Version = $Matches[3].Trim()
        $UpdateInfo = $Matches[4].Trim()
        
        # Filter out repeating headers and empty lines
        if ($Name -eq "Name" -or $Name -eq "Nom" -or $PkgID -eq "ID" -or [string]::IsNullOrWhiteSpace($Name)) { continue }

        # Determine if update is available
        $IsUpdate = $false
        $NewVersion = ""
        if ($UpdateInfo -match 'winget|msstore') {
            $IsUpdate = $true
            if ($UpdateInfo -match '(\d+\.[\d\.]+)') { $NewVersion = $Matches[1] }
        }

        # Installation Date Retrieval
        $FormattedDate = "---"
        try {
            $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            $InstallDate = (Get-ItemProperty $RegPath -ErrorAction SilentlyContinue | 
                            Where-Object { $_.DisplayName -eq $Name -or $_.PSChildName -eq $PkgID } | 
                            Select-Object -ExpandProperty InstallDate -ErrorAction SilentlyContinue | Select-Object -First 1)
            
            if ($InstallDate -match '^\d{8}$') {
                $FormattedDate = [DateTime]::ParseExact($InstallDate, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
            }
        } catch { $FormattedDate = "---" }

        $GlobalInstalled += [PSCustomObject]@{
            Index       = $Counter++
            Name        = $Name
            ID          = $PkgID
            Version     = $Version
            IsUpdate    = $IsUpdate
            NewVersion  = $NewVersion
            InstallDate = $FormattedDate
        }
    }
}

# --- AGGREGATED METRICS FOR DASHBOARD CARDS ---
$TotalApps      = $GlobalInstalled.Count
$UpdateCount    = ($GlobalInstalled | Where-Object { $_.IsUpdate }).Count
$UpToDateCount  = $TotalApps - $UpdateCount
$GeneratedAt    = (Get-Date).ToString("yyyy-MM-dd HH:mm")

# --- 2. GENERATE WEB DASHBOARD (ULTRA PRO - ENGLISH) ---
$HtmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>System Inventory Dashboard</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --bg: #020617; --card: #020617; --card-elevated: #020617; --text: #e5e7eb; --accent: #38bdf8; --success: #22c55e; --warning: #f59e0b; --border: #1f2937; }
        body { font-family: 'Segoe UI', system-ui, -apple-system, BlinkMacSystemFont, sans-serif; background: radial-gradient(circle at top, #0f172a 0, #020617 50%, #000 100%); color: var(--text); margin: 0; padding: 32px; }
        .container { max-width: 1320px; margin: auto; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; background: linear-gradient(135deg, rgba(15,23,42,.95), rgba(8,47,73,.98)); padding: 24px 26px; border-radius: 18px; border: 1px solid rgba(56,189,248,.25); box-shadow: 0 18px 45px rgba(15,23,42,.9); position: relative; overflow: hidden; }
        .header::after { content: ""; position: absolute; inset: -40%; background: radial-gradient(circle at top right, rgba(56,189,248,.16), transparent 60%); opacity: .9; pointer-events: none; }
        .header-main { position: relative; z-index: 1; }
        h1 { margin: 0; font-size: 1.9em; letter-spacing: .04em; color: var(--accent); display: flex; align-items: center; gap: 14px; text-transform: uppercase; }
        h1 i { padding: 10px; border-radius: 999px; background: radial-gradient(circle at 30% 0, rgba(56,189,248,.65), rgba(37,99,235,.7)); box-shadow: 0 0 30px rgba(56,189,248,.65); }
        .subtitle { margin-top: 6px; font-size: 0.9em; color: #9ca3af; }
        .meta { position: relative; z-index: 1; text-align: right; font-size: 0.85em; color: #9ca3af; }
        .meta strong { color: #e5e7eb; }
        .meta .chip { display: inline-flex; align-items: center; gap: 6px; padding: 6px 12px; border-radius: 999px; background: rgba(15,23,42,.7); border: 1px solid rgba(148,163,184,.45); font-size: 0.8em; margin-top: 6px; }
        .meta .chip i { color: var(--accent); }

        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 18px; margin-bottom: 26px; }
        .metric-card { position: relative; overflow: hidden; background: radial-gradient(circle at top, #020617 0, #020617 45%, #020617 100%); border-radius: 16px; padding: 16px 18px; border: 1px solid rgba(30,64,175,.7); box-shadow: 0 14px 32px rgba(15,23,42,.85); display: flex; flex-direction: column; gap: 10px; }
        .metric-card::before { content: ""; position: absolute; inset: -40%; background: radial-gradient(circle at top left, rgba(56,189,248,.18), transparent 60%); opacity: .65; pointer-events: none; }
        .metric-inner { position: relative; z-index: 1; display: flex; justify-content: space-between; gap: 10px; align-items: center; }
        .metric-label { font-size: 0.78em; text-transform: uppercase; letter-spacing: .13em; color: #9ca3af; }
        .metric-value { font-size: 1.6em; font-weight: 700; color: #f9fafb; }
        .metric-icon { width: 36px; height: 36px; border-radius: 999px; display: inline-flex; align-items: center; justify-content: center; background: rgba(15,23,42,.92); border: 1px solid rgba(148,163,184,.5); color: var(--accent); box-shadow: 0 0 20px rgba(56,189,248,.5); }
        .metric-footnote { font-size: 0.77em; color: #9ca3af; margin-top: 2px; }
        .metric-primary { border-color: rgba(56,189,248,.7); }
        .metric-success { border-color: rgba(34,197,94,.75); }
        .metric-warning { border-color: rgba(245,158,11,.8); }
        .metric-neutral { border-color: rgba(148,163,184,.7); }

        .search-container { position: relative; margin-bottom: 18px; }
        #SearchInput { width: 100%; padding: 13px 48px; background: rgba(15,23,42,.95); border: 1px solid rgba(55,65,81,.95); border-radius: 999px; color: white; font-size: 0.95em; box-sizing: border-box; box-shadow: 0 12px 24px rgba(15,23,42,.75); }
        #SearchInput::placeholder { color: #64748b; }
        .search-icon { position: absolute; left: 18px; top: 10px; color: #64748b; }
        
        .table-shell { background: linear-gradient(145deg, rgba(15,23,42,.98), rgba(15,23,42,.96)); border-radius: 18px; padding: 14px 18px 20px; border: 1px solid rgba(31,41,55,.95); box-shadow: 0 18px 45px rgba(15,23,42,.9); }
        .table-title { display: flex; justify-content: space-between; align-items: baseline; margin: 0 0 8px; }
        .table-title h2 { font-size: 0.95em; font-weight: 600; color: #e5e7eb; text-transform: uppercase; letter-spacing: .16em; }
        .table-title span { font-size: 0.8em; color: #9ca3af; }
        .table-filters { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; justify-content: flex-end; }
        .table-filters label { font-size: 0.8em; color: #9ca3af; }
        .table-filters select { background: rgba(15,23,42,.95); border-radius: 999px; border: 1px solid rgba(55,65,81,.95); color: #e5e7eb; padding: 7px 14px; font-size: 0.8em; outline: none; }

        .pagination { display: flex; align-items: center; justify-content: flex-end; gap: 10px; margin-top: 10px; font-size: 0.8em; color: #9ca3af; }
        .pagination button { background: rgba(15,23,42,.95); border-radius: 999px; border: 1px solid rgba(55,65,81,.95); color: #e5e7eb; padding: 6px 14px; font-size: 0.8em; cursor: pointer; }
        .pagination button:disabled { opacity: 0.4; cursor: default; }
        
        table { width: 100%; border-collapse: separate; border-spacing: 0 7px; table-layout: fixed; }
        thead th { padding: 10px 14px; text-align: left; color: #9ca3af; font-weight: 500; font-size: 0.78em; text-transform: uppercase; letter-spacing: 0.13em; background: rgba(15,23,42,0.98); position: sticky; top: 0; z-index: 2; }
        tr.app-row { background: radial-gradient(circle at top left, rgba(30,64,175,.25), rgba(15,23,42,1)); transition: all 0.18s ease-out; border-radius: 10px; }
        tr.app-row:nth-child(even) { background: radial-gradient(circle at top, rgba(15,23,42,1), rgba(15,23,42,1)); }
        tr.app-row:hover { transform: translateY(-1px); box-shadow: 0 10px 28px rgba(15,23,42,.95); }
        td { padding: 10px 14px; border-top: 1px solid rgba(30,64,175,.5); border-bottom: 1px solid rgba(15,23,42,1); font-size: 0.9em; }
        td:first-child { border-left: 1px solid rgba(30,64,175,.5); border-top-left-radius: 10px; border-bottom-left-radius: 10px; }
        td:last-child { border-right: 1px solid rgba(15,23,42,1); border-top-right-radius: 10px; border-bottom-right-radius: 10px; }
        .col-index { width: 52px; }
        .col-name { width: 30%; }
        .col-id { width: 26%; }
        .col-version { width: 10%; white-space: nowrap; }
        .col-date { width: 16%; white-space: nowrap; }
        .col-status { width: 16%; }

        .badge-status { padding: 5px 12px; border-radius: 999px; font-size: 0.75em; font-weight: 600; display: inline-flex; align-items: center; gap: 7px; letter-spacing: .08em; text-transform: uppercase; }
        .up-to-date { background: rgba(34,197,94,.1); color: var(--success); border: 1px solid rgba(34,197,94,.7); box-shadow: 0 0 18px rgba(34,197,94,.35); }
        .needs-update { background: rgba(245,158,11,.1); color: var(--warning); border: 1px solid rgba(245,158,11,.9); box-shadow: 0 0 18px rgba(245,158,11,.4); }
        
        .pkg-id { font-family: 'Consolas', monospace; font-size: 0.82em; color: #9ca3af; }
        .app-name { font-weight: 600; font-size: 0.96em; color: #f9fafb; }
        .index-muted { color: #6b7280; font-size: 0.82em; }

        @media (max-width: 960px) {
            body { padding: 20px 16px; }
            .header { flex-direction: column; align-items: flex-start; gap: 16px; }
            .meta { text-align: left; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-main">
                <h1><i class="fas fa-microchip"></i>Winget Package Inventory Report</h1>
                <div class="subtitle">Winget-managed software inventory for this workstation</div>
            </div>
            <div class="meta">
                <div>Hostname: <strong>$env:COMPUTERNAME</strong></div>
                <div class="chip"><i class="fas fa-clock"></i> Snapshot generated: <strong>$GeneratedAt</strong></div>
            </div>
        </div>

        <div class="summary-grid">
            <div class="metric-card metric-primary">
                <div class="metric-inner">
                    <div>
                        <div class="metric-label">Installed Applications</div>
                        <div class="metric-value">$TotalApps</div>
                        <div class="metric-footnote">Discovered across the current Windows profile.</div>
                    </div>
                    <div class="metric-icon"><i class="fas fa-layer-group"></i></div>
                </div>
            </div>
            <div class="metric-card metric-success">
                <div class="metric-inner">
                    <div>
                        <div class="metric-label">Up To Date</div>
                        <div class="metric-value">$UpToDateCount</div>
                        <div class="metric-footnote">Applications already on the latest known release.</div>
                    </div>
                    <div class="metric-icon"><i class="fas fa-badge-check"></i></div>
                </div>
            </div>
            <div class="metric-card metric-warning">
                <div class="metric-inner">
                    <div>
                        <div class="metric-label">Pending Updates</div>
                        <div class="metric-value">$UpdateCount</div>
                        <div class="metric-footnote">Applications with at least one update advertised by winget.</div>
                    </div>
                    <div class="metric-icon"><i class="fas fa-arrow-trend-up"></i></div>
                </div>
            </div>
            <div class="metric-card metric-neutral">
                <div class="metric-inner">
                    <div>
                        <div class="metric-label">Snapshot Context</div>
                        <div class="metric-value"><span style="font-size:0.95em;">$env:COMPUTERNAME</span></div>
                        <div class="metric-footnote">Static HTML report generated from the latest inventory scan.</div>
                    </div>
                    <div class="metric-icon"><i class="fas fa-server"></i></div>
                </div>
            </div>
        </div>

        <div class="search-container">
            <i class="fas fa-search search-icon"></i>
            <input type="text" id="SearchInput" onkeyup="filterTable()" placeholder="Quick search for name, ID, or version...">
        </div>

        <div class="table-shell">
            <div class="table-title">
                <h2>Application Inventory</h2>
                <span>Real-time snapshot exported from winget list</span>
            </div>
            <div class="table-filters">
                <label for="StatusFilter">Status filter:</label>
                <select id="StatusFilter" onchange="filterTable()">
                    <option value="all">All applications</option>
                    <option value="up">Up to date</option>
                    <option value="update">Update available</option>
                </select>
            </div>
            <table id="InventoryTable">
                <thead>
                    <tr>
                        <th class="col-index">#</th>
                        <th class="col-name">Application Name</th>
                        <th class="col-id">Package ID</th>
                        <th class="col-version">Version</th>
                        <th class="col-date">Install Date</th>
                        <th class="col-status">Maintenance Status</th>
                    </tr>
                </thead>
                <tbody>
"@

$HtmlBody = ""
foreach ($App in $GlobalInstalled) {
    # Détermine le badge (vert / rouge) et l'état pour le filtre
    if ($App.IsUpdate) {
        $RowStatus = "update"
        # Icône rouge uniquement si une mise à jour est dispo
        $StatusBadge = "<span class='badge-status needs-update' title='Update available'><i class='fas fa-circle' style='color:#ef4444;'></i></span>"
    } else {
        $RowStatus = "up"
        # Icône verte uniquement si l'application est à jour
        $StatusBadge = "<span class='badge-status up-to-date' title='Up to date'><i class='fas fa-circle' style='color:#22c55e;'></i></span>"
    }

    $HtmlBody += @"
        <tr class="app-row" data-status="$RowStatus">
            <td class="col-index" style="color:#64748b">#$($App.Index)</td>
            <td class="app-name col-name">$($App.Name)</td>
            <td class="pkg-id col-id">$($App.ID)</td>
            <td class="col-version">$($App.Version)</td>
            <td class="col-date" style="color:#94a3b8">$($App.InstallDate)</td>
            <td class="col-status">$StatusBadge</td>
        </tr>
"@
}

$HtmlFooter = @"
            </tbody>
        </table>
        <div class="pagination">
            <button id="PrevPage" onclick="changePage(-1)">Previous</button>
            <span id="PageInfo">Page 1 / 1</span>
            <button id="NextPage" onclick="changePage(1)">Next</button>
        </div>
    </div>
    <script>
    var currentPage = 1;
    var pageSize = 50;

    function filterTable() {
        var input = document.getElementById("SearchInput");
        var filter = input.value.toUpperCase();
        var statusSelect = document.getElementById("StatusFilter");
        var statusFilter = statusSelect ? statusSelect.value : "all";
        var tr = document.getElementById("InventoryTable").getElementsByClassName("app-row");
        for (var i = 0; i < tr.length; i++) {
            var text = tr[i].textContent || tr[i].innerText;
            var rowStatus = tr[i].getAttribute("data-status") || "";
            var matchesText = text.toUpperCase().indexOf(filter) > -1;
            var matchesStatus = (statusFilter === "all" || statusFilter === rowStatus);
            tr[i].dataset.included = (matchesText && matchesStatus) ? "1" : "0";
        }
        currentPage = 1;
        renderPage();
    }

    function renderPage() {
        var tr = document.getElementById("InventoryTable").getElementsByClassName("app-row");
        var includedRows = [];
        for (var i = 0; i < tr.length; i++) {
            if (tr[i].dataset.included === "1" || tr[i].dataset.included === undefined) {
                includedRows.push(tr[i]);
            } else {
                tr[i].style.display = "none";
            }
        }

        var totalItems = includedRows.length;
        var totalPages = Math.max(1, Math.ceil(totalItems / pageSize));
        if (currentPage > totalPages) currentPage = totalPages;

        for (var j = 0; j < includedRows.length; j++) {
            var startIndex = (currentPage - 1) * pageSize;
            var endIndex = startIndex + pageSize;
            if (j >= startIndex && j < endIndex) {
                includedRows[j].style.display = "";
            } else {
                includedRows[j].style.display = "none";
            }
        }

        var pageInfo = document.getElementById("PageInfo");
        if (pageInfo) {
            pageInfo.textContent = "Page " + currentPage + " / " + totalPages;
        }

        var prevBtn = document.getElementById("PrevPage");
        var nextBtn = document.getElementById("NextPage");
        if (prevBtn) prevBtn.disabled = (currentPage <= 1);
        if (nextBtn) nextBtn.disabled = (currentPage >= totalPages);
    }

    function changePage(delta) {
        currentPage += delta;
        if (currentPage < 1) currentPage = 1;
        renderPage();
    }

    window.addEventListener("load", function () {
        filterTable();
    });
    </script>
</body>
</html>
"@

$HtmlHeader + $HtmlBody + $HtmlFooter | Out-File -FilePath $ReportPath -Encoding utf8
Write-Host "[+] Dashboard generated successfully." -ForegroundColor Green
Start-Process $ReportPath

# --- 3. DYNAMIC DISCOVERY MODE ---
Write-Host "`n" + ("=" * 55) -ForegroundColor Cyan
Write-Host "                WINGET DISCOVERY MODE" -ForegroundColor White
Write-Host ("=" * 55) -ForegroundColor Cyan

# --- Category + curated catalog (reliable winget IDs) ---
$Categories = [ordered]@{
    "1" = @{ Name = "Web Browsers"; Examples = @("Google Chrome", "Mozilla Firefox", "Microsoft Edge") }
    "2" = @{ Name = "Developer Tools"; Examples = @("Visual Studio Code", "Git", "Node.js") }
    "3" = @{ Name = "Office Suites"; Examples = @("LibreOffice", "ONLYOFFICE", "Adobe Acrobat Reader") }
    "4" = @{ Name = "Multimedia"; Examples = @("VLC", "Spotify", "OBS Studio") }
    "5" = @{ Name = "Security / System Utilities"; Examples = @("7-Zip", "PowerToys", "Sysinternals") }
}

$Catalog = [ordered]@{
    "1" = @(
        @{ Name = "Google Chrome"; Id = "Google.Chrome" }
        @{ Name = "Mozilla Firefox"; Id = "Mozilla.Firefox" }
        @{ Name = "Microsoft Edge"; Id = "Microsoft.Edge" }
        @{ Name = "Brave"; Id = "Brave.Brave" }
        @{ Name = "Opera"; Id = "Opera.Opera" }
    )
    "2" = @(
        @{ Name = "Visual Studio Code"; Id = "Microsoft.VisualStudioCode" }
        @{ Name = "Git"; Id = "Git.Git" }
        @{ Name = "Node.js LTS"; Id = "OpenJS.NodeJS.LTS" }
        @{ Name = "Python 3"; Id = "Python.Python.3" }
        @{ Name = "Docker Desktop"; Id = "Docker.DockerDesktop" }
    )
    "3" = @(
        @{ Name = "LibreOffice"; Id = "TheDocumentFoundation.LibreOffice" }
        @{ Name = "ONLYOFFICE Desktop Editors"; Id = "ONLYOFFICE.DesktopEditors" }
        @{ Name = "Adobe Acrobat Reader"; Id = "Adobe.Acrobat.Reader.64-bit" }
    )
    "4" = @(
        @{ Name = "VLC media player"; Id = "VideoLAN.VLC" }
        @{ Name = "Spotify"; Id = "Spotify.Spotify" }
        @{ Name = "OBS Studio"; Id = "OBSProject.OBSStudio" }
        @{ Name = "HandBrake"; Id = "HandBrake.HandBrake" }
    )
    "5" = @(
        @{ Name = "7-Zip"; Id = "7zip.7zip" }
        @{ Name = "Microsoft PowerToys"; Id = "Microsoft.PowerToys" }
        @{ Name = "Sysinternals Suite"; Id = "Microsoft.Sysinternals" }
        @{ Name = "Everything (Voidtools)"; Id = "voidtools.Everything" }
    )
}

function Show-Categories {
    Write-Host ""
    Write-Host "Available categories:" -ForegroundColor Cyan
    foreach ($key in $Categories.Keys) {
        $cat = $Categories[$key]
        $examples = ($cat.Examples -join ", ")
        Write-Host ("  [{0}] {1}  (e.g.: {2})" -f $key, $cat.Name, $examples) -ForegroundColor Gray
    }
    Write-Host "  [0] No category (free search)" -ForegroundColor Gray
}

function Show-CategoryApps([string]$catKey) {
    $apps = $Catalog[$catKey]
    Write-Host ""
    Write-Host ("Category: {0}" -f $Categories[$catKey].Name) -ForegroundColor Cyan
    Write-Host "Available apps in this category:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $apps.Count; $i++) {
        $n = $i + 1
        Write-Host ("  [{0}] {1}  ({2})" -f $n, $apps[$i].Name, $apps[$i].Id) -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  - Enter app index(es) (e.g. 1,3) to install selected" -ForegroundColor Gray
    Write-Host "  - A = install ALL apps from this category" -ForegroundColor Gray
    Write-Host "  - P = preview app details (winget show)" -ForegroundColor Gray
    Write-Host "  - B = back to categories" -ForegroundColor Gray
    Write-Host "  - Q = quit discovery mode" -ForegroundColor Gray
}

function Parse-Indexes([string]$text, [int]$max) {
    $result = @()
    $parts = $text -split '[,\s]+' | Where-Object { $_ -ne "" }
    foreach ($p in $parts) {
        if ($p -notmatch '^\d+$') { continue }
        $v = [int]$p
        if ($v -ge 1 -and $v -le $max) { $result += $v }
    }
    $result | Select-Object -Unique
}

while ($true) {
    Show-Categories
    $CatChoice = Read-Host "`nChoose ONE category number (0-5, or Q to quit)"
    if ([string]::IsNullOrWhiteSpace($CatChoice)) { $CatChoice = "0" }
    $CatChoice = $CatChoice.Trim()

    if ($CatChoice.ToUpper() -eq "Q") {
        Write-Host "`n[EXIT] Leaving discovery mode." -ForegroundColor Cyan
        break
    }

    # --- Free search mode (unchanged behavior, but still looped) ---
    if ($CatChoice -eq "0") {
        $Query = Read-Host "`nEnter application name to search (Q to quit, ENTER to go back)"
        if ([string]::IsNullOrWhiteSpace($Query)) { continue }
        if ($Query.ToUpper() -eq "Q") { Write-Host "`n[EXIT] Leaving discovery mode." -ForegroundColor Cyan; break }

        Write-Host "`n[*] Searching global repositories for: '$Query'..." -ForegroundColor Gray
        $SearchResults = winget search $Query --accept-source-agreements | Select-Object -Skip 2

        $SearchMenu = @()
        foreach ($line in $SearchResults) {
            if ($line -match '^(.*?)\s{2,}(.*?)\s{2,}(.*?)\s{2,}(.*)$') {
                $SearchMenu += [PSCustomObject]@{ '#' = $SearchMenu.Count; Name = $Matches[1].Trim(); ID = $Matches[2].Trim(); Version = $Matches[3].Trim() }
            }
        }

        if ($SearchMenu.Count -eq 0) {
            Write-Host "No results found. Returning to menu..." -ForegroundColor Red
            continue
        }
        $SearchMenu | Format-Table -AutoSize

        $Selection = Read-Host ">>> Enter index(es) to install (ENTER to go back, Q to quit)"
        if ([string]::IsNullOrWhiteSpace($Selection)) { continue }
        if ($Selection.ToUpper() -eq 'Q') { Write-Host "`n[EXIT] Leaving discovery mode." -ForegroundColor Cyan; break }

        try {
            $Indices = $Selection.Split(',').Trim()
            foreach ($idx in $Indices) {
                $Target = $SearchMenu[[int]$idx]
                Write-Host "`n[INSTALLING] $($Target.Name)..." -ForegroundColor Magenta
                winget install --id $Target.ID --silent --accept-package-agreements --accept-source-agreements
            }
            Write-Host "`n[FINISHED] Selected applications installed (or already present)." -ForegroundColor Cyan
        } catch {
            Write-Host "Invalid selection or installation failed." -ForegroundColor Red
        }
        continue
    }

    if (-not $Catalog.Contains($CatChoice)) {
        Write-Host "Invalid category. Please choose 0-5." -ForegroundColor Yellow
        continue
    }

    # --- Category guided mode ---
    $apps = $Catalog[$CatChoice]
    while ($true) {
        Show-CategoryApps -catKey $CatChoice
        $Action = Read-Host ">>> Choose apps or option (ENTER=B)"
        if ([string]::IsNullOrWhiteSpace($Action)) { break }

        $upper = $Action.Trim().ToUpper()
        if ($upper -eq "B") { break }
        if ($upper -eq "Q") { Write-Host "`n[EXIT] Leaving discovery mode." -ForegroundColor Cyan; break 2 }

        if ($upper -eq "P") {
            $pSel = Read-Host "Preview which app index(es)? (e.g. 1,3 or ENTER=back)"
            if ([string]::IsNullOrWhiteSpace($pSel)) { continue }
            $idxs = Parse-Indexes -text $pSel -max $apps.Count
            if ($idxs.Count -eq 0) { Write-Host "No valid indexes." -ForegroundColor Yellow; continue }
            foreach ($i in $idxs) {
                $app = $apps[$i - 1]
                Write-Host "`n[PREVIEW] $($app.Name) ($($app.Id))" -ForegroundColor Cyan
                winget show --id $app.Id --accept-source-agreements
            }
            continue
        }

        $selectedApps = @()
        if ($upper -eq "A") {
            $selectedApps = $apps
        } else {
            $idxs = Parse-Indexes -text $Action -max $apps.Count
            if ($idxs.Count -eq 0) { Write-Host "No valid indexes. Use e.g. 1,3 or A." -ForegroundColor Yellow; continue }
            foreach ($i in $idxs) { $selectedApps += $apps[$i - 1] }
        }

        # Constraint example: avoid accidental huge installs
        if ($selectedApps.Count -gt 10) {
            Write-Host "Safety limit: max 10 apps per batch. Please select fewer apps." -ForegroundColor Yellow
            continue
        }

        Write-Host ""
        Write-Host "Selected for install:" -ForegroundColor Cyan
        foreach ($a in $selectedApps) { Write-Host ("  - {0} ({1})" -f $a.Name, $a.Id) -ForegroundColor Gray }

        $Confirm = Read-Host "`nProceed with installation? (Y/N)"
        if ($Confirm.Trim().ToUpper() -ne "Y") {
            Write-Host "Cancelled. Returning to category list..." -ForegroundColor Yellow
            continue
        }

        foreach ($a in $selectedApps) {
            Write-Host "`n[INSTALLING] $($a.Name)..." -ForegroundColor Magenta
            winget install --id $a.Id --silent --accept-package-agreements --accept-source-agreements
        }
        Write-Host "`n[FINISHED] Installation batch completed." -ForegroundColor Cyan
    }
}