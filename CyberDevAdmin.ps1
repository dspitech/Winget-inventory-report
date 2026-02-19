$ErrorActionPreference = 'SilentlyContinue'

# CATALOGUE MIS A JOUR (AngryIP supprimé, System Informer & OpenSSL corrigés)
$Apps = @(
    # --- CYBER & ANALYSE SYSTEME ---
    @{Id='PortSwigger.BurpSuite.Community'; Name='Burp Suite'; Cat='Cyber'}
    @{Id='SleuthKit.Autopsy'; Name='Autopsy'; Cat='Cyber'}
    @{Id='ZAP.ZAP'; Name='OWASP ZAP'; Cat='Cyber'}
    @{Id='Insecure.Nmap'; Name='Nmap'; Cat='Cyber'}
    @{Id='WiresharkFoundation.Wireshark'; Name='Wireshark'; Cat='Cyber'}
    @{Id='KeePassXCTeam.KeePassXC'; Name='KeePassXC'; Cat='Cyber'}
    @{Id='WinsiderSS.SystemInformer'; Name='System Informer'; Cat='Cyber'}
    
    # --- DEV & ENVIRONNEMENT ---
    @{Id='Microsoft.VisualStudioCode'; Name='VS Code'; Cat='Dev'}
    @{Id='Python.Python.3.12'; Name='Python 3'; Cat='Dev'}
    @{Id='OpenJS.NodeJS.LTS'; Name='NodeJS'; Cat='Dev'}
    @{Id='Git.Git'; Name='Git'; Cat='Dev'}
    @{Id='FireDaemon.OpenSSL'; Name='OpenSSL 3'; Cat='Dev'}
    
    # --- DEVOPS & INFRA ---
    @{Id='Docker.DockerDesktop'; Name='Docker'; Cat='DevOps'}
    @{Id='Hashicorp.Vagrant'; Name='Vagrant'; Cat='DevOps'}
    @{Id='Hashicorp.Terraform'; Name='Terraform'; Cat='DevOps'}
    @{Id='Postman.Postman'; Name='Postman'; Cat='DevOps'}
    
    # --- ADMIN & UTILITAIRES ---
    @{Id='Microsoft.Sysinternals.Suite'; Name='Sysinternals'; Cat='Admin'}
    @{Id='Mobatek.MobaXterm'; Name='MobaXterm'; Cat='Admin'}
    @{Id='PuTTY.PuTTY'; Name='PuTTY'; Cat='Admin'}
    @{Id='WinSCP.WinSCP'; Name='WinSCP'; Cat='Admin'}
    @{Id='voidtools.Everything'; Name='Everything'; Cat='Admin'}
    @{Id='Microsoft.PowerToys'; Name='PowerToys'; Cat='Admin'}
    @{Id='7zip.7zip'; Name='7-Zip'; Cat='System'}
    @{Id='BleachBit.BleachBit'; Name='BleachBit'; Cat='System'}
    @{Id='CrystalDewWorld.CrystalDiskInfo'; Name='DiskInfo'; Cat='System'}
    @{Id='CPUID.CPU-Z'; Name='CPU-Z'; Cat='System'}
    @{Id='Brave.Brave'; Name='Brave Browser'; Cat='Tools'}
)

while ($true) {
    # Scan de la liste actuelle (Out-String pour stabiliser la détection)
    $listRaw = winget list --accept-source-agreements | Out-String
    
    Clear-Host
    Write-Host '=== ARSENAL CYBER (VERSION NETTOYEE) ===' -ForegroundColor Cyan
    Write-Host '-------------------------------------------------------'
    
    $FullList = @()
    $count = 1
    $MissingCount = 0
    
    foreach ($a in $Apps) {
        # Détection hybride (ID ou Nom) insensible à la casse
        $isDone = ($listRaw -like "*$($a.Id)*") -or ($listRaw -like "*$($a.Name)*")
        
        $tag = '[ ]'; $color = 'White'
        if ($isDone) { 
            $tag = '[OK]'; $color = 'DarkGray' 
        } else { 
            $MissingCount++ 
        }
        
        # Affichage formaté sans caractères spéciaux risqués
        $row = '{0:D2}. {1,-10} | {2,-15} {3}' -f $count, $a.Cat, $a.Name, $tag
        Write-Host $row -ForegroundColor $color
        
        $FullList += [PSCustomObject]@{Idx=$count; Id=$a.Id; Name=$a.Name; Done=$isDone}
        $count++
    }

    if ($MissingCount -eq 0) {
        Write-Host '-------------------------------------------------------'
        Write-Host 'TOUS LES SYSTEMES SONT OPERATIONNELS' -ForegroundColor Green
        break
    }

    Write-Host '-------------------------------------------------------'
    Write-Host 'A: Tout | S: Selection | Q: Quitter | U: Update'
    
    $ans = (Read-Host 'Action').ToUpper()
    if ($ans -eq 'Q') { break }
    if ($ans -eq 'U') { 
        winget upgrade --all --accept-package-agreements --accept-source-agreements
        continue 
    }

    $ToInstall = @()
    if ($ans -eq 'A') { $ToInstall = $FullList | Where-Object { !$_.Done } }
    elseif ($ans -eq 'S') {
        $nums = Read-Host 'Numeros'
        foreach ($n in $nums.Split(',')) {
            if ([int]::TryParse($n.Trim(), [ref]$idx)) {
                $match = $FullList | Where-Object { $_.Idx -eq $idx }
                if ($match) { $ToInstall += $match }
            }
        }
    }

    foreach ($t in $ToInstall) {
        Write-Host "Installation de : $($t.Name)"
        winget install --id $t.Id --exact --accept-package-agreements --accept-source-agreements --silent
    }
    Start-Sleep -Seconds 2
}
