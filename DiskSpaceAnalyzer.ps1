<#
.SYNOPSIS
    Analyseur d'Espace Disque - DiskSpaceAnalyzer

.DESCRIPTION
    Script PowerShell qui analyse l'espace disque du profil utilisateur courant
    et affiche les resultats via une interface graphique WPF moderne.
    Genere un rapport HTML interactif et detecte les fichiers en double.

.PARAMETER Path
    Chemin a analyser. Par defaut : C:\Users\%username%

.PARAMETER ExportPath
    Chemin pour l'export HTML. Par defaut : %TEMP%

.EXAMPLE
    .\DiskSpaceAnalyzer.ps1
    Lance l'analyseur sur le profil utilisateur courant

.EXAMPLE
    .\DiskSpaceAnalyzer.ps1 -Path "D:\Data"
    Analyse le dossier specifie

.NOTES
    Version: 1.1
    Auteur: DiskSpaceAnalyzer
    Date: Janvier 2026
    Prerequis: Windows 10/11, PowerShell 5.1+, .NET Framework 4.5+
#>

param(
    [string]$Path = $env:USERPROFILE,
    [string]$ExportPath = $env:TEMP,
    [string]$SupportEmail = "support@entreprise.com"
)

#region Configuration et Variables Globales
$Script:Version = "1.5"
$Script:AppName = "Analyseur d'Espace Disque"
$Script:CompanyName = "Mon Entreprise"
$Script:AnalysisResults = $null
$Script:CancelRequested = $false
$Script:TotalFilesScanned = 0
$Script:TotalSize = 0
$Script:ForcedTheme = $null  # $null = auto, "Light" ou "Dark"
$Script:IsAdmin = $false     # Sera defini au demarrage

# ============================================
# CONFIGURATION SMTP - A MODIFIER PAR L'ADMIN
# ============================================
$Script:SmtpServer = "smtp.entreprise.com"      # Serveur SMTP
$Script:SmtpPort = 587                           # Port SMTP (25, 465, 587)
$Script:SmtpUser = "noreply@entreprise.com"     # Login SMTP
$Script:SmtpPassword = "MotDePasseSMTP"         # Mot de passe SMTP
$Script:SmtpTo = "admin-it@entreprise.com"      # Destinataire des rapports
$Script:SmtpFrom = "noreply@entreprise.com"     # Expediteur
$Script:SmtpUseSsl = $true                       # Utiliser SSL/TLS
# ============================================

#endregion

#region Chargement des Assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Web
#endregion

#region Fonctions Systeme

# Detecte si l'utilisateur a des droits administrateur (local ou domaine)
function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)

    # Verifier admin local
    $isLocalAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Verifier admin domaine (Domain Admins, Enterprise Admins)
    $isDomainAdmin = $false
    try {
        $isDomainAdmin = $principal.IsInRole("Domain Admins") -or
                         $principal.IsInRole("Enterprise Admins") -or
                         $principal.IsInRole("Administrateurs du domaine") -or
                         $principal.IsInRole("Admins du domaine")
    } catch {
        # Pas dans un domaine ou erreur - ignorer
    }

    return ($isLocalAdmin -or $isDomainAdmin)
}

# Envoie un email avec le log de nettoyage
function Send-CleanupReport {
    param(
        [string]$LogContent,
        [string]$CleanupSummary
    )

    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $dateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $subject = "Nettoyage Disque - $computerName - $userName"

    $body = @"
RAPPORT DE NETTOYAGE DISQUE
============================
Ordinateur: $computerName
Utilisateur: $userName
Date: $dateTime
Mode: $(if ($Script:IsAdmin) { "Administrateur" } else { "Utilisateur" })

RESUME DU NETTOYAGE
-------------------
$CleanupSummary

JOURNAL COMPLET
---------------
$LogContent
"@

    try {
        $smtpClient = New-Object System.Net.Mail.SmtpClient($Script:SmtpServer, $Script:SmtpPort)
        $smtpClient.EnableSsl = $Script:SmtpUseSsl
        $smtpClient.Credentials = New-Object System.Net.NetworkCredential($Script:SmtpUser, $Script:SmtpPassword)

        $mailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.From = $Script:SmtpFrom
        $mailMessage.To.Add($Script:SmtpTo)
        $mailMessage.Subject = $subject
        $mailMessage.Body = $body
        $mailMessage.IsBodyHtml = $false

        $smtpClient.Send($mailMessage)

        return @{ Success = $true; Message = "Email envoye avec succes a $($Script:SmtpTo)" }
    } catch {
        return @{ Success = $false; Message = "Erreur envoi email: $($_.Exception.Message)" }
    } finally {
        if ($mailMessage) { $mailMessage.Dispose() }
        if ($smtpClient) { $smtpClient.Dispose() }
    }
}

# Obtenir le chemin du dossier Telechargements
function Get-DownloadsPath {
    $shell = New-Object -ComObject Shell.Application
    $downloads = $shell.Namespace('shell:Downloads')
    if ($downloads) {
        return $downloads.Self.Path
    }
    return Join-Path $env:USERPROFILE "Downloads"
}

#endregion

#region Fonctions de Creation d'Objets

function New-AnalyzedFile {
    param([System.IO.FileInfo]$FileInfo)

    return [PSCustomObject]@{
        Name = $FileInfo.Name
        FullPath = $FileInfo.FullName
        Directory = $FileInfo.DirectoryName
        Size = $FileInfo.Length
        SizeFormatted = Format-FileSize -Bytes $FileInfo.Length
        DateModified = $FileInfo.LastWriteTime
        DateCreated = $FileInfo.CreationTime
        Extension = $FileInfo.Extension.ToLower()
    }
}

function New-FolderNode {
    param(
        [string]$Name,
        [string]$FullPath
    )

    return [PSCustomObject]@{
        Name = $Name
        FullPath = $FullPath
        Size = [long]0
        SizeFormatted = "0 octets"
        FileCount = 0
        SubfolderCount = 0
        PercentOfTotal = [double]0
        Children = [System.Collections.ArrayList]@()
    }
}

function New-DuplicateGroup {
    param(
        [string]$FileName,
        [long]$FileSize,
        [datetime]$DateModified
    )

    return [PSCustomObject]@{
        FileName = $FileName
        FileSize = $FileSize
        FileSizeFormatted = Format-FileSize -Bytes $FileSize
        DateModified = $DateModified
        Locations = [System.Collections.ArrayList]@()
        WastedSpace = [long]0
        WastedSpaceFormatted = "0 octets"
    }
}

function New-AnalysisResults {
    param([string]$RootPath)

    $driveTotal = 0
    $driveFree = 0

    try {
        $drive = [System.IO.Path]::GetPathRoot($RootPath)
        if ($drive) {
            $driveLetter = $drive.Substring(0, 1)
            $driveInfo = New-Object System.IO.DriveInfo($driveLetter)
            $driveTotal = $driveInfo.TotalSize
            $driveFree = $driveInfo.AvailableFreeSpace
        }
    } catch {
        # Ignorer les erreurs
    }

    return [PSCustomObject]@{
        RootPath = $RootPath
        AnalysisDate = Get-Date
        TotalSize = [long]0
        TotalSizeFormatted = "0 octets"
        TotalFiles = 0
        TotalFolders = 0
        DriveTotal = $driveTotal
        DriveFree = $driveFree
        RootNode = $null
        AllFiles = [System.Collections.ArrayList]@()
        Top20Files = [System.Collections.ArrayList]@()
        Duplicates = [System.Collections.ArrayList]@()
        ExtensionStats = @{}
        Errors = [System.Collections.ArrayList]@()
    }
}

function Add-DuplicateLocation {
    param(
        [PSCustomObject]$DupGroup,
        [string]$Path
    )

    [void]$DupGroup.Locations.Add($Path)
    $DupGroup.WastedSpace = ($DupGroup.Locations.Count - 1) * $DupGroup.FileSize
    $DupGroup.WastedSpaceFormatted = Format-FileSize -Bytes $DupGroup.WastedSpace
}
#endregion

#region Fonctions Utilitaires

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} Go" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} Mo" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N2} Ko" -f ($Bytes / 1KB) }
    else { return "$Bytes octets" }
}

function Get-SystemTheme {
    # Si un theme est force, l'utiliser
    if ($Script:ForcedTheme) {
        return $Script:ForcedTheme
    }
    # Sinon, detecter le theme systeme
    try {
        $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $value = Get-ItemPropertyValue -Path $regPath -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
        if ($value -eq 0) { return "Dark" }
        else { return "Light" }
    } catch {
        return "Light"
    }
}

function Open-InExplorer {
    param([string]$Path)
    if (Test-Path $Path) {
        if ((Get-Item $Path).PSIsContainer) {
            Start-Process explorer.exe -ArgumentList $Path
        } else {
            Start-Process explorer.exe -ArgumentList "/select,`"$Path`""
        }
    }
}
#endregion

#region Fonctions d'Analyse

function Scan-Directory {
    param(
        [string]$DirectoryPath,
        [PSCustomObject]$ParentNode,
        [scriptblock]$ProgressCallback,
        [ref]$Results,
        [hashtable]$Filters
    )

    if ($Script:CancelRequested) { return }

    try {
        $items = Get-ChildItem -Path $DirectoryPath -Force -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            if ($Script:CancelRequested) { return }

            if ($item.PSIsContainer) {
                $childNode = New-FolderNode -Name $item.Name -FullPath $item.FullName
                $ParentNode.SubfolderCount++
                [void]$ParentNode.Children.Add($childNode)

                # Verifier si le dossier est exclu
                $excluded = $false
                if ($Filters -and $Filters.ExcludedFolders) {
                    foreach ($excludedFolder in $Filters.ExcludedFolders) {
                        if ($item.FullName -like "*$excludedFolder*") {
                            $excluded = $true
                            break
                        }
                    }
                }

                if (-not $excluded) {
                    Scan-Directory -DirectoryPath $item.FullName -ParentNode $childNode -ProgressCallback $ProgressCallback -Results $Results -Filters $Filters
                }

                $ParentNode.Size += $childNode.Size
                $ParentNode.FileCount += $childNode.FileCount
                $childNode.SizeFormatted = Format-FileSize -Bytes $childNode.Size

            } else {
                $ParentNode.FileCount++
                $Script:TotalFilesScanned++

                try {
                    $fileSize = $item.Length
                    $ParentNode.Size += $fileSize
                    $Script:TotalSize += $fileSize

                    $include = $true

                    if ($Filters) {
                        if ($Filters.ExcludedExtensions -and $Filters.ExcludedExtensions -contains $item.Extension.ToLower()) {
                            $include = $false
                        }
                        if ($Filters.MinSize -and $fileSize -lt $Filters.MinSize) {
                            $include = $false
                        }
                        if ($Filters.OlderThan -and $item.LastWriteTime -gt $Filters.OlderThan) {
                            $include = $false
                        }
                    }

                    if ($include) {
                        $analyzedFile = New-AnalyzedFile -FileInfo $item
                        [void]$Results.Value.AllFiles.Add($analyzedFile)

                        $ext = $item.Extension.ToLower()
                        if (-not $ext) { $ext = "(sans extension)" }
                        if (-not $Results.Value.ExtensionStats.ContainsKey($ext)) {
                            $Results.Value.ExtensionStats[$ext] = @{ Count = 0; Size = 0 }
                        }
                        $Results.Value.ExtensionStats[$ext].Count++
                        $Results.Value.ExtensionStats[$ext].Size += $fileSize
                    }

                    if ($ProgressCallback -and ($Script:TotalFilesScanned % 100 -eq 0)) {
                        & $ProgressCallback $item.DirectoryName $Script:TotalFilesScanned
                    }

                } catch {
                    [void]$Results.Value.Errors.Add("Erreur lecture: $($item.FullName) - $($_.Exception.Message)")
                }
            }
        }
    } catch {
        [void]$Results.Value.Errors.Add("Erreur acces dossier: $DirectoryPath - $($_.Exception.Message)")
    }
}

function Find-Duplicates {
    param([System.Collections.ArrayList]$Files)

    $duplicates = [System.Collections.ArrayList]@()

    $groups = $Files | Group-Object -Property { "$($_.Name.ToLower())|$($_.DateModified.ToString('yyyy-MM-dd HH:mm:ss'))" } | Where-Object { $_.Count -gt 1 }

    foreach ($group in $groups) {
        $firstFile = $group.Group[0]
        $dupGroup = New-DuplicateGroup -FileName $firstFile.Name -FileSize $firstFile.Size -DateModified $firstFile.DateModified

        foreach ($file in $group.Group) {
            Add-DuplicateLocation -DupGroup $dupGroup -Path $file.FullPath
        }

        [void]$duplicates.Add($dupGroup)
    }

    return $duplicates
}

function Start-Analysis {
    param(
        [string]$RootPath,
        [scriptblock]$ProgressCallback,
        [hashtable]$Filters
    )

    $Script:CancelRequested = $false
    $Script:TotalFilesScanned = 0
    $Script:TotalSize = 0

    $results = New-AnalysisResults -RootPath $RootPath
    $rootNode = New-FolderNode -Name (Split-Path $RootPath -Leaf) -FullPath $RootPath

    $resultsRef = [ref]$results

    # Verifier si on doit analyser des sous-dossiers specifiques
    $isUserProfile = ($RootPath -eq $env:USERPROFILE) -or ($RootPath -eq [Environment]::GetFolderPath('UserProfile'))
    $hasSelectedSubfolders = $Filters -and $Filters.SelectedSubfolders -and $Filters.SelectedSubfolders.Count -gt 0

    if ($isUserProfile -and $hasSelectedSubfolders) {
        # Mode sous-dossiers : analyser uniquement les sous-dossiers selectionnes
        foreach ($subfolder in $Filters.SelectedSubfolders) {
            if ($Script:CancelRequested) { break }

            $subfolderPath = Join-Path $RootPath $subfolder
            if (Test-Path $subfolderPath) {
                $childNode = New-FolderNode -Name $subfolder -FullPath $subfolderPath
                $rootNode.SubfolderCount++
                [void]$rootNode.Children.Add($childNode)

                Scan-Directory -DirectoryPath $subfolderPath -ParentNode $childNode -ProgressCallback $ProgressCallback -Results $resultsRef -Filters $Filters

                $rootNode.Size += $childNode.Size
                $rootNode.FileCount += $childNode.FileCount
                $childNode.SizeFormatted = Format-FileSize -Bytes $childNode.Size
            }
        }
    } else {
        # Mode normal : analyser tout le dossier
        Scan-Directory -DirectoryPath $RootPath -ParentNode $rootNode -ProgressCallback $ProgressCallback -Results $resultsRef -Filters $Filters
    }

    $rootNode.SizeFormatted = Format-FileSize -Bytes $rootNode.Size
    $results.RootNode = $rootNode
    $results.TotalSize = $Script:TotalSize
    $results.TotalFiles = $Script:TotalFilesScanned

    # Compter les dossiers selon le mode
    if ($isUserProfile -and $hasSelectedSubfolders) {
        $folderCount = 0
        foreach ($subfolder in $Filters.SelectedSubfolders) {
            $subfolderPath = Join-Path $RootPath $subfolder
            if (Test-Path $subfolderPath) {
                $folderCount += (Get-ChildItem -Path $subfolderPath -Directory -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
                $folderCount++ # Compter le sous-dossier lui-meme
            }
        }
        $results.TotalFolders = $folderCount
    } else {
        $results.TotalFolders = (Get-ChildItem -Path $RootPath -Directory -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
    }

    $results.TotalSizeFormatted = Format-FileSize -Bytes $results.TotalSize

    if ($results.TotalSize -gt 0) {
        Update-FolderPercentages -Node $rootNode -TotalSize $results.TotalSize
    }

    # Top 20 fichiers
    $top20 = $results.AllFiles | Sort-Object -Property Size -Descending | Select-Object -First 20
    foreach ($file in $top20) {
        [void]$results.Top20Files.Add($file)
    }

    # Detection des doublons
    $results.Duplicates = Find-Duplicates -Files $results.AllFiles

    return $results
}

function Update-FolderPercentages {
    param(
        [PSCustomObject]$Node,
        [long]$TotalSize
    )

    if ($TotalSize -gt 0) {
        $Node.PercentOfTotal = [math]::Round(($Node.Size / $TotalSize) * 100, 2)
    }

    foreach ($child in $Node.Children) {
        Update-FolderPercentages -Node $child -TotalSize $TotalSize
    }
}
#endregion

#region Generation du Rapport HTML

function Generate-HTMLReport {
    param([PSCustomObject]$Results)

    $chartLabels = ($Results.ExtensionStats.GetEnumerator() | Sort-Object { $_.Value.Size } -Descending | Select-Object -First 10 | ForEach-Object { "'$($_.Key)'" }) -join ","
    $chartData = ($Results.ExtensionStats.GetEnumerator() | Sort-Object { $_.Value.Size } -Descending | Select-Object -First 10 | ForEach-Object { [math]::Round($_.Value.Size / 1MB, 2) }) -join ","

    $top20Rows = ""
    $rank = 1
    foreach ($file in $Results.Top20Files) {
        $escapedPath = [System.Web.HttpUtility]::HtmlEncode($file.FullPath)
        $escapedName = [System.Web.HttpUtility]::HtmlEncode($file.Name)
        $top20Rows += @"
        <tr>
            <td>$rank</td>
            <td>$escapedName</td>
            <td class="path-cell" title="$escapedPath">$escapedPath</td>
            <td>$($file.SizeFormatted)</td>
            <td>$($file.DateModified.ToString('dd/MM/yyyy HH:mm'))</td>
            <td>$($file.DateCreated.ToString('dd/MM/yyyy HH:mm'))</td>
            <td>$($file.Extension)</td>
            <td><a href="file:///$($file.Directory -replace '\\','/')" class="btn-open">Ouvrir</a></td>
        </tr>
"@
        $rank++
    }

    $duplicatesHtml = ""
    $totalWasted = 0
    foreach ($dup in $Results.Duplicates) {
        $totalWasted += $dup.WastedSpace
        $locations = ($dup.Locations | ForEach-Object { "<li><a href='file:///$($_ -replace '\\','/')'>$([System.Web.HttpUtility]::HtmlEncode($_))</a></li>" }) -join ""
        $duplicatesHtml += @"
        <div class="duplicate-group">
            <div class="duplicate-header">
                <strong>$([System.Web.HttpUtility]::HtmlEncode($dup.FileName))</strong>
                <span class="duplicate-info">$($dup.FileSizeFormatted) | $($dup.Locations.Count) occurrences | Espace gaspille: $($dup.WastedSpaceFormatted)</span>
            </div>
            <ul class="duplicate-locations">$locations</ul>
        </div>
"@
    }

    $totalWastedFormatted = Format-FileSize -Bytes $totalWasted
    $driveUsedPercent = if ($Results.DriveTotal -gt 0) { [math]::Round((($Results.DriveTotal - $Results.DriveFree) / $Results.DriveTotal) * 100, 1) } else { 0 }

    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Rapport d'Analyse Disque - $($Results.RootPath)</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-primary: #ffffff;
            --bg-secondary: #f8f9fa;
            --text-primary: #212529;
            --text-secondary: #6c757d;
            --border-color: #dee2e6;
            --accent-color: #0d6efd;
            --success-color: #198754;
            --warning-color: #ffc107;
            --danger-color: #dc3545;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #1a1a2e;
                --bg-secondary: #16213e;
                --text-primary: #e8e8e8;
                --text-secondary: #a0a0a0;
                --border-color: #3a3a5c;
                --accent-color: #4dabf7;
            }
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            padding: 20px;
        }

        .container { max-width: 1400px; margin: 0 auto; }

        header {
            background: linear-gradient(135deg, var(--accent-color), #6610f2);
            color: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        header h1 { font-size: 2em; margin-bottom: 10px; }
        header .meta { opacity: 0.9; font-size: 0.95em; }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .stat-card {
            background: var(--bg-secondary);
            padding: 20px;
            border-radius: 10px;
            border: 1px solid var(--border-color);
            text-align: center;
        }

        .stat-card .value {
            font-size: 2em;
            font-weight: bold;
            color: var(--accent-color);
        }

        .stat-card .label {
            color: var(--text-secondary);
            font-size: 0.9em;
            margin-top: 5px;
        }

        .section {
            background: var(--bg-secondary);
            padding: 25px;
            border-radius: 12px;
            margin-bottom: 25px;
            border: 1px solid var(--border-color);
        }

        .section h2 {
            color: var(--accent-color);
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid var(--border-color);
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9em;
        }

        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }

        th {
            background: var(--bg-primary);
            font-weight: 600;
            position: sticky;
            top: 0;
            cursor: pointer;
        }

        th:hover { background: var(--border-color); }

        tr:hover { background: var(--bg-primary); }

        .path-cell {
            max-width: 300px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .btn-open {
            background: var(--accent-color);
            color: white;
            padding: 6px 12px;
            border-radius: 5px;
            text-decoration: none;
            font-size: 0.85em;
            transition: opacity 0.2s;
        }

        .btn-open:hover { opacity: 0.8; }

        .chart-container {
            max-width: 500px;
            margin: 0 auto;
        }

        .duplicate-group {
            background: var(--bg-primary);
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 15px;
            border-left: 4px solid var(--warning-color);
        }

        .duplicate-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 10px;
        }

        .duplicate-info {
            font-size: 0.85em;
            color: var(--text-secondary);
        }

        .duplicate-locations {
            list-style: none;
            padding-left: 20px;
        }

        .duplicate-locations li {
            padding: 5px 0;
            border-bottom: 1px dashed var(--border-color);
        }

        .duplicate-locations a {
            color: var(--accent-color);
            text-decoration: none;
            word-break: break-all;
        }

        .duplicate-locations a:hover { text-decoration: underline; }

        .email-btn {
            display: inline-block;
            background: var(--success-color);
            color: white;
            padding: 12px 25px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            margin-top: 20px;
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .email-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.2);
        }

        .search-box {
            width: 100%;
            padding: 12px;
            border: 1px solid var(--border-color);
            border-radius: 8px;
            background: var(--bg-primary);
            color: var(--text-primary);
            font-size: 1em;
            margin-bottom: 15px;
        }

        .export-btn {
            background: var(--accent-color);
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.9em;
            margin-right: 10px;
        }

        .export-btn:hover { opacity: 0.9; }

        footer {
            text-align: center;
            padding: 20px;
            color: var(--text-secondary);
            font-size: 0.85em;
        }

        @media (max-width: 768px) {
            .stats-grid { grid-template-columns: repeat(2, 1fr); }
            table { font-size: 0.8em; }
            th, td { padding: 8px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Rapport d'Analyse Disque</h1>
            <div class="meta">
                <p><strong>Chemin analyse:</strong> $($Results.RootPath)</p>
                <p><strong>Date d'analyse:</strong> $($Results.AnalysisDate.ToString('dd/MM/yyyy HH:mm:ss'))</p>
                <p><strong>Utilisateur:</strong> $env:USERNAME</p>
            </div>
        </header>

        <div class="stats-grid">
            <div class="stat-card">
                <div class="value">$($Results.TotalSizeFormatted)</div>
                <div class="label">Espace utilise</div>
            </div>
            <div class="stat-card">
                <div class="value">$($Results.TotalFiles.ToString('N0'))</div>
                <div class="label">Fichiers</div>
            </div>
            <div class="stat-card">
                <div class="value">$($Results.TotalFolders.ToString('N0'))</div>
                <div class="label">Dossiers</div>
            </div>
            <div class="stat-card">
                <div class="value">$($Results.Duplicates.Count)</div>
                <div class="label">Groupes de doublons</div>
            </div>
            <div class="stat-card">
                <div class="value">$totalWastedFormatted</div>
                <div class="label">Espace gaspille (doublons)</div>
            </div>
            <div class="stat-card">
                <div class="value">$driveUsedPercent%</div>
                <div class="label">Lecteur utilise</div>
            </div>
        </div>

        <div class="section">
            <h2>Repartition par type de fichier</h2>
            <div class="chart-container">
                <canvas id="extensionChart"></canvas>
            </div>
        </div>

        <div class="section">
            <h2>Top 20 des fichiers les plus volumineux</h2>
            <input type="text" class="search-box" id="searchTop20" placeholder="Rechercher dans le tableau..." onkeyup="filterTable('top20Table', this.value)">
            <button class="export-btn" onclick="exportTableToCSV('top20Table', 'top20_fichiers.csv')">Exporter en CSV</button>
            <div style="overflow-x: auto; margin-top: 15px;">
                <table id="top20Table">
                    <thead>
                        <tr>
                            <th onclick="sortTable('top20Table', 0)">#</th>
                            <th onclick="sortTable('top20Table', 1)">Nom</th>
                            <th onclick="sortTable('top20Table', 2)">Chemin</th>
                            <th onclick="sortTable('top20Table', 3)">Taille</th>
                            <th onclick="sortTable('top20Table', 4)">Modifie</th>
                            <th onclick="sortTable('top20Table', 5)">Cree</th>
                            <th onclick="sortTable('top20Table', 6)">Extension</th>
                            <th>Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        $top20Rows
                    </tbody>
                </table>
            </div>
        </div>

        <div class="section">
            <h2>Fichiers en double detectes ($($Results.Duplicates.Count) groupes)</h2>
            <p style="margin-bottom: 15px; color: var(--text-secondary);">
                Espace total gaspille par les doublons: <strong>$totalWastedFormatted</strong>
            </p>
            $duplicatesHtml
        </div>

        <div class="section" style="text-align: center;">
            <h2>Actions</h2>
            <a href="mailto:$($Script:SupportEmail)?subject=Rapport%20d'analyse%20disque%20-%20$env:USERNAME%20-%20$($Results.AnalysisDate.ToString('yyyy-MM-dd'))&body=Veuillez%20trouver%20ci-joint%20le%20rapport%20d'analyse%20disque." class="email-btn">
                Envoyer au support
            </a>
        </div>

        <footer>
            <p>Rapport genere par DiskSpaceAnalyzer v$($Script:Version)</p>
            <p>$($Results.AnalysisDate.ToString('dd/MM/yyyy HH:mm:ss'))</p>
        </footer>
    </div>

    <script>
        // Graphique de repartition
        const ctx = document.getElementById('extensionChart').getContext('2d');
        new Chart(ctx, {
            type: 'doughnut',
            data: {
                labels: [$chartLabels],
                datasets: [{
                    data: [$chartData],
                    backgroundColor: [
                        '#0d6efd', '#6610f2', '#6f42c1', '#d63384', '#dc3545',
                        '#fd7e14', '#ffc107', '#198754', '#20c997', '#0dcaf0'
                    ],
                    borderWidth: 2,
                    borderColor: getComputedStyle(document.documentElement).getPropertyValue('--bg-primary')
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'right',
                        labels: { color: getComputedStyle(document.documentElement).getPropertyValue('--text-primary') }
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                return context.label + ': ' + context.parsed + ' Mo';
                            }
                        }
                    }
                }
            }
        });

        // Fonction de recherche/filtrage
        function filterTable(tableId, searchText) {
            const table = document.getElementById(tableId);
            const rows = table.getElementsByTagName('tbody')[0].getElementsByTagName('tr');
            const filter = searchText.toLowerCase();

            for (let row of rows) {
                let text = row.textContent.toLowerCase();
                row.style.display = text.includes(filter) ? '' : 'none';
            }
        }

        // Fonction de tri
        let sortDirections = {};
        function sortTable(tableId, colIndex) {
            const table = document.getElementById(tableId);
            const tbody = table.getElementsByTagName('tbody')[0];
            const rows = Array.from(tbody.getElementsByTagName('tr'));

            const key = tableId + '_' + colIndex;
            sortDirections[key] = !sortDirections[key];
            const direction = sortDirections[key] ? 1 : -1;

            rows.sort((a, b) => {
                let aVal = a.cells[colIndex].textContent.trim();
                let bVal = b.cells[colIndex].textContent.trim();

                let aNum = parseFloat(aVal.replace(/[^\d.-]/g, ''));
                let bNum = parseFloat(bVal.replace(/[^\d.-]/g, ''));

                if (!isNaN(aNum) && !isNaN(bNum)) {
                    return (aNum - bNum) * direction;
                }
                return aVal.localeCompare(bVal) * direction;
            });

            rows.forEach(row => tbody.appendChild(row));
        }

        // Export CSV
        function exportTableToCSV(tableId, filename) {
            const table = document.getElementById(tableId);
            const rows = table.querySelectorAll('tr');
            let csv = [];

            for (let row of rows) {
                let cols = row.querySelectorAll('td, th');
                let rowData = [];
                for (let i = 0; i < cols.length - 1; i++) {
                    let text = cols[i].textContent.replace(/"/g, '""');
                    rowData.push('"' + text + '"');
                }
                csv.push(rowData.join(';'));
            }

            const blob = new Blob([csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            link.href = URL.createObjectURL(blob);
            link.download = filename;
            link.click();
        }
    </script>
</body>
</html>
"@

    return $html
}
#endregion

#region Interface WPF

function Show-MainWindow {
    param([string]$AnalysisPath)

    $theme = Get-SystemTheme

    if ($theme -eq "Dark") {
        # Theme Sombre - couleurs plus contrastees
        $bgPrimary = "#1e1e2e"       # Fond principal (bleu-noir)
        $bgSecondary = "#2a2a3e"     # Fond secondaire (plus clair)
        $bgTertiary = "#363650"      # Fond tertiaire pour les cartes
        $textPrimary = "#ffffff"     # Texte principal (blanc pur)
        $textSecondary = "#b8b8c8"   # Texte secondaire (gris clair)
        $textMuted = "#8888a0"       # Texte attenue
        $borderColor = "#4a4a6a"     # Bordures
        $accentColor = "#6ea8fe"     # Accent bleu clair
        $successColor = "#75b798"    # Vert
        $warningColor = "#ffda6a"    # Jaune
        $dangerColor = "#ea868f"     # Rouge clair
        $themeIcon = "☀"            # Icone soleil (pour passer en clair)
    } else {
        # Theme Clair - couleurs classiques
        $bgPrimary = "#ffffff"       # Fond principal (blanc)
        $bgSecondary = "#f5f5f5"     # Fond secondaire (gris tres clair)
        $bgTertiary = "#e9ecef"      # Fond tertiaire
        $textPrimary = "#1a1a1a"     # Texte principal (noir)
        $textSecondary = "#555555"   # Texte secondaire (gris fonce)
        $textMuted = "#888888"       # Texte attenue
        $borderColor = "#cccccc"     # Bordures
        $accentColor = "#0d6efd"     # Accent bleu
        $successColor = "#198754"    # Vert
        $warningColor = "#ffc107"    # Jaune
        $dangerColor = "#dc3545"     # Rouge
        $themeIcon = "☾"            # Icone lune (pour passer en sombre)
    }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$($Script:AppName) - $AnalysisPath"
        Height="800" Width="1200"
        MinHeight="600" MinWidth="900"
        WindowStartupLocation="CenterScreen"
        Background="$bgPrimary">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="$accentColor"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="5"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextBlock.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Opacity" Value="0.85"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="TabStyle" TargetType="TabItem">
            <Setter Property="Foreground" Value="$textPrimary"/>
            <Setter Property="Background" Value="$bgSecondary"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderBrush" Value="$borderColor"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1,1,1,0"
                                Padding="{TemplateBinding Padding}" Margin="2,0,2,0" CornerRadius="5,5,0,0">
                            <ContentPresenter x:Name="ContentSite" ContentSource="Header"
                                              HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextBlock.Foreground="{TemplateBinding Foreground}"
                                              TextBlock.FontWeight="{TemplateBinding FontWeight}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="$bgPrimary"/>
                                <Setter Property="Foreground" Value="$accentColor"/>
                                <Setter TargetName="Border" Property="BorderThickness" Value="1,1,1,0"/>
                                <Setter TargetName="Border" Property="Margin" Value="2,-2,2,0"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="$bgTertiary"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="$bgTertiary"/>
            <Setter Property="Foreground" Value="$textPrimary"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="$borderColor"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextBlock.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="$borderColor"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button">
            <Setter Property="Background" Value="$dangerColor"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="5"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              TextBlock.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Opacity" Value="0.85"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Barre d'outils -->
        <Border Grid.Row="0" Background="$bgSecondary" Padding="15" BorderBrush="$borderColor" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Partie gauche : boutons et chemin -->
                <StackPanel Grid.Column="0" Orientation="Horizontal">
                    <Button x:Name="btnAnalyze" Content="Analyser" Style="{StaticResource ModernButton}" Margin="0,0,10,0"/>
                    <Button x:Name="btnExport" Content="Exporter HTML" Style="{StaticResource ModernButton}" Margin="0,0,10,0" IsEnabled="False"/>
                    <Button x:Name="btnCancel" Content="Annuler" Style="{StaticResource DangerButton}" Margin="0,0,10,0" IsEnabled="False"/>
                    <Separator Margin="10,0" Background="$borderColor"/>
                    <TextBlock Text="Chemin:" VerticalAlignment="Center" Foreground="$textSecondary" Margin="0,0,10,0"/>
                    <TextBox x:Name="txtPath" Width="350" Padding="8" Background="$bgPrimary" Foreground="$textPrimary"
                             BorderBrush="$borderColor" BorderThickness="1" VerticalContentAlignment="Center"
                             Text="$AnalysisPath"/>
                    <Button x:Name="btnBrowse" Content="..." Style="{StaticResource ModernButton}" Margin="5,0,0,0" Padding="10,8"/>
                </StackPanel>

                <!-- Partie droite : theme et signature -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="btnToggleTheme" Style="{StaticResource SecondaryButton}" Margin="0,0,15,0" Padding="10,8" ToolTip="Changer de theme">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="$themeIcon" FontSize="14" Margin="0,0,5,0"/>
                            <TextBlock Text="Theme"/>
                        </StackPanel>
                    </Button>
                    <Separator Margin="0,0,15,0" Background="$borderColor"/>
                    <StackPanel Orientation="Vertical" VerticalAlignment="Center">
                        <TextBlock Text="$($Script:CompanyName)" FontWeight="Bold" Foreground="$accentColor" FontSize="12"/>
                        <TextBlock Text="DiskSpaceAnalyzer v$($Script:Version)" Foreground="$textMuted" FontSize="10"/>
                    </StackPanel>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Contenu principal avec onglets -->
        <TabControl Grid.Row="1" x:Name="tabControl" Background="$bgPrimary" BorderBrush="$borderColor">

            <!-- Onglet Vue d'ensemble -->
            <TabItem Header="Vue d'ensemble" Style="{StaticResource TabStyle}">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <Grid Margin="20">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <UniformGrid Grid.Row="0" Columns="4" Margin="0,0,0,20">
                            <Border Background="$bgSecondary" Margin="5" Padding="20" CornerRadius="10" BorderBrush="$borderColor" BorderThickness="1">
                                <StackPanel HorizontalAlignment="Center">
                                    <TextBlock x:Name="txtTotalSize" Text="--" FontSize="28" FontWeight="Bold" Foreground="$accentColor" HorizontalAlignment="Center"/>
                                    <TextBlock Text="Espace utilise" Foreground="$textSecondary" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Border>
                            <Border Background="$bgSecondary" Margin="5" Padding="20" CornerRadius="10" BorderBrush="$borderColor" BorderThickness="1">
                                <StackPanel HorizontalAlignment="Center">
                                    <TextBlock x:Name="txtTotalFiles" Text="--" FontSize="28" FontWeight="Bold" Foreground="$accentColor" HorizontalAlignment="Center"/>
                                    <TextBlock Text="Fichiers" Foreground="$textSecondary" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Border>
                            <Border Background="$bgSecondary" Margin="5" Padding="20" CornerRadius="10" BorderBrush="$borderColor" BorderThickness="1">
                                <StackPanel HorizontalAlignment="Center">
                                    <TextBlock x:Name="txtTotalFolders" Text="--" FontSize="28" FontWeight="Bold" Foreground="$accentColor" HorizontalAlignment="Center"/>
                                    <TextBlock Text="Dossiers" Foreground="$textSecondary" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Border>
                            <Border Background="$bgSecondary" Margin="5" Padding="20" CornerRadius="10" BorderBrush="$borderColor" BorderThickness="1">
                                <StackPanel HorizontalAlignment="Center">
                                    <TextBlock x:Name="txtDuplicates" Text="--" FontSize="28" FontWeight="Bold" Foreground="$warningColor" HorizontalAlignment="Center"/>
                                    <TextBlock Text="Doublons" Foreground="$textSecondary" HorizontalAlignment="Center"/>
                                </StackPanel>
                            </Border>
                        </UniformGrid>

                        <Border Grid.Row="1" Background="$bgSecondary" Padding="20" CornerRadius="10" BorderBrush="$borderColor" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Top 5 des types de fichiers" FontSize="16" FontWeight="SemiBold" Foreground="$textPrimary" Margin="0,0,0,15"/>
                                <ItemsControl x:Name="lstExtensions">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Grid Margin="0,5">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="100"/>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="100"/>
                                                </Grid.ColumnDefinitions>
                                                <TextBlock Text="{Binding Extension}" Foreground="$textPrimary" FontWeight="SemiBold"/>
                                                <ProgressBar Grid.Column="1" Value="{Binding Percent}" Maximum="100" Height="20" Margin="10,0" Background="$bgPrimary" Foreground="$accentColor"/>
                                                <TextBlock Grid.Column="2" Text="{Binding SizeFormatted}" Foreground="$textSecondary" HorizontalAlignment="Right"/>
                                            </Grid>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </StackPanel>
                        </Border>
                    </Grid>
                </ScrollViewer>
            </TabItem>

            <!-- Onglet Hierarchie -->
            <TabItem Header="Hierarchie" Style="{StaticResource TabStyle}">
                <Grid Margin="20">
                    <TreeView x:Name="treeHierarchy" Background="$bgPrimary" BorderBrush="$borderColor" Foreground="$textPrimary">
                        <TreeView.ItemTemplate>
                            <HierarchicalDataTemplate ItemsSource="{Binding Children}">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="300"/>
                                        <ColumnDefinition Width="100"/>
                                        <ColumnDefinition Width="80"/>
                                        <ColumnDefinition Width="80"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="{Binding Name}" Foreground="$textPrimary"/>
                                    <TextBlock Grid.Column="1" Text="{Binding SizeFormatted}" Foreground="$accentColor" FontWeight="SemiBold"/>
                                    <TextBlock Grid.Column="2" Text="{Binding PercentOfTotal, StringFormat={}{0:N1}%}" Foreground="$textSecondary"/>
                                    <TextBlock Grid.Column="3" Text="{Binding FileCount}" Foreground="$textSecondary"/>
                                </Grid>
                            </HierarchicalDataTemplate>
                        </TreeView.ItemTemplate>
                    </TreeView>
                </Grid>
            </TabItem>

            <!-- Onglet Top 20 -->
            <TabItem Header="Top 20" Style="{StaticResource TabStyle}">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <TextBox x:Name="txtSearchTop20" Grid.Row="0" Margin="0,0,0,15" Padding="10"
                             Background="$bgSecondary" Foreground="$textPrimary" BorderBrush="$borderColor"
                             Text="" Tag="Rechercher..."/>

                    <DataGrid x:Name="gridTop20" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True"
                              Background="$bgPrimary" BorderBrush="$borderColor" GridLinesVisibility="Horizontal"
                              RowBackground="$bgPrimary" AlternatingRowBackground="$bgSecondary"
                              HeadersVisibility="Column" CanUserResizeRows="False">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Nom" Binding="{Binding Name}" Width="200"/>
                            <DataGridTextColumn Header="Chemin" Binding="{Binding Directory}" Width="300"/>
                            <DataGridTextColumn Header="Taille" Binding="{Binding SizeFormatted}" Width="100"/>
                            <DataGridTextColumn Header="Modifie" Binding="{Binding DateModified, StringFormat=dd/MM/yyyy HH:mm}" Width="130"/>
                            <DataGridTextColumn Header="Cree" Binding="{Binding DateCreated, StringFormat=dd/MM/yyyy HH:mm}" Width="130"/>
                            <DataGridTextColumn Header="Extension" Binding="{Binding Extension}" Width="80"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </Grid>
            </TabItem>

            <!-- Onglet Doublons -->
            <TabItem Header="Doublons" Style="{StaticResource TabStyle}">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="$bgSecondary" Padding="15" CornerRadius="8" Margin="0,0,0,15">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock x:Name="txtDuplicatesInfo" Text="Aucune analyse effectuee" Foreground="$textPrimary" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>

                    <ListView x:Name="lstDuplicates" Grid.Row="1" Background="$bgPrimary" BorderBrush="$borderColor">
                        <ListView.ItemTemplate>
                            <DataTemplate>
                                <Border Background="$bgSecondary" Padding="15" Margin="0,5" CornerRadius="8" BorderBrush="$warningColor" BorderThickness="0,0,0,3">
                                    <StackPanel>
                                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                            <TextBlock Text="{Binding FileName}" FontWeight="Bold" Foreground="$textPrimary" FontSize="14"/>
                                            <TextBlock Text=" - " Foreground="$textSecondary"/>
                                            <TextBlock Text="{Binding FileSizeFormatted}" Foreground="$accentColor"/>
                                            <TextBlock Text=" - " Foreground="$textSecondary"/>
                                            <TextBlock Text="{Binding Locations.Count, StringFormat={}{0} occurrences}" Foreground="$textSecondary"/>
                                            <TextBlock Text=" - Gaspille: " Foreground="$textSecondary" Margin="10,0,0,0"/>
                                            <TextBlock Text="{Binding WastedSpaceFormatted}" Foreground="$dangerColor" FontWeight="SemiBold"/>
                                        </StackPanel>
                                        <ItemsControl ItemsSource="{Binding Locations}">
                                            <ItemsControl.ItemTemplate>
                                                <DataTemplate>
                                                    <TextBlock Text="{Binding}" Foreground="$textSecondary" Margin="20,2,0,2"/>
                                                </DataTemplate>
                                            </ItemsControl.ItemTemplate>
                                        </ItemsControl>
                                    </StackPanel>
                                </Border>
                            </DataTemplate>
                        </ListView.ItemTemplate>
                    </ListView>
                </Grid>
            </TabItem>

            <!-- Onglet Filtres -->
            <TabItem Header="Filtres" Style="{StaticResource TabStyle}">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <Border Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Sous-dossiers utilisateur a analyser" FontSize="14" FontWeight="SemiBold" Foreground="$textPrimary" Margin="0,0,0,10"/>
                                <TextBlock Text="Selectionnez les sous-dossiers du dossier utilisateur a inclure dans l'analyse:" Foreground="$textSecondary" Margin="0,0,0,10" TextWrapping="Wrap"/>
                                <WrapPanel>
                                    <CheckBox x:Name="chkDocuments" Content="Documents" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkDesktop" Content="Bureau" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkDownloads" Content="Telechargements" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkPictures" Content="Images" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkVideos" Content="Videos" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkMusic" Content="Musique" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkAppDataLocal" Content="AppData\\Local" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkAppDataRoaming" Content="AppData\\Roaming" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkOneDrive" Content="OneDrive" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                </WrapPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                    <Button x:Name="btnSelectAllFolders" Content="Tout selectionner" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0" Padding="10,5"/>
                                    <Button x:Name="btnDeselectAllFolders" Content="Tout deselectionner" Style="{StaticResource SecondaryButton}" Padding="10,5"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <Border Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Extensions a exclure" FontSize="14" FontWeight="SemiBold" Foreground="$textPrimary" Margin="0,0,0,10"/>
                                <WrapPanel>
                                    <CheckBox x:Name="chkTmp" Content=".tmp" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkLog" Content=".log" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkBak" Content=".bak" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkCache" Content=".cache" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkOst" Content=".ost" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkPst" Content=".pst" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                </WrapPanel>
                                <TextBox x:Name="txtCustomExtensions" Margin="0,10,0,0" Padding="10"
                                         Background="$bgPrimary" Foreground="$textPrimary" BorderBrush="$borderColor"
                                         Text="" Tag="Extensions personnalisees (separer par des virgules: .xyz, .abc)"/>
                            </StackPanel>
                        </Border>

                        <Border Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Filtre par taille" FontSize="14" FontWeight="SemiBold" Foreground="$textPrimary" Margin="0,0,0,10"/>
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="Taille minimum:" Foreground="$textSecondary" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                    <TextBox x:Name="txtMinSize" Width="100" Padding="8" Background="$bgPrimary"
                                             Foreground="$textPrimary" BorderBrush="$borderColor" Text="0"/>
                                    <TextBlock Text="Mo" Foreground="$textSecondary" VerticalAlignment="Center" Margin="10,0,0,0"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <Border Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Filtre par date" FontSize="14" FontWeight="SemiBold" Foreground="$textPrimary" Margin="0,0,0,10"/>
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="Fichiers non modifies depuis:" Foreground="$textSecondary" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                    <TextBox x:Name="txtOlderThan" Width="100" Padding="8" Background="$bgPrimary"
                                             Foreground="$textPrimary" BorderBrush="$borderColor" Text="0"/>
                                    <TextBlock Text="jours (0 = desactive)" Foreground="$textSecondary" VerticalAlignment="Center" Margin="10,0,0,0"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <Border Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Dossiers a exclure" FontSize="14" FontWeight="SemiBold" Foreground="$textPrimary" Margin="0,0,0,10"/>
                                <WrapPanel>
                                    <CheckBox x:Name="chkAppData" Content="AppData\Local\Temp" Foreground="$textPrimary" Margin="0,0,15,5" IsChecked="True"/>
                                    <CheckBox x:Name="chkCache2" Content="Cache" Foreground="$textPrimary" Margin="0,0,15,5"/>
                                </WrapPanel>
                                <TextBox x:Name="txtCustomFolders" Margin="0,10,0,0" Padding="10"
                                         Background="$bgPrimary" Foreground="$textPrimary" BorderBrush="$borderColor"
                                         Text="" Tag="Dossiers personnalises (separer par des virgules)"/>
                            </StackPanel>
                        </Border>

                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                            <Button x:Name="btnApplyFilters" Content="Appliquer et Re-analyser" Style="{StaticResource ModernButton}" Margin="0,0,10,0"/>
                            <Button x:Name="btnResetFilters" Content="Reinitialiser" Style="{StaticResource SecondaryButton}"/>
                        </StackPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Onglet Nettoyage -->
            <TabItem Header="Nettoyage" Style="{StaticResource TabStyle}">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <!-- Mode de fonctionnement -->
                        <Border x:Name="borderModeInfo" Background="$accentColor" Padding="12" CornerRadius="8" Margin="0,0,0,15">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock x:Name="txtModeIcon" Text="👤" FontSize="18" Margin="0,0,10,0" VerticalAlignment="Center"/>
                                <StackPanel>
                                    <TextBlock x:Name="txtModeTitle" Text="Mode Utilisateur" FontWeight="SemiBold" Foreground="White"/>
                                    <TextBlock x:Name="txtModeDesc" Text="Analyse limitee a votre profil utilisateur" Foreground="White" Opacity="0.9" FontSize="12"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- ETAPE 1: Analyse -->
                        <Border Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15" BorderBrush="$borderColor" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Border Background="$accentColor" Width="28" Height="28" CornerRadius="14">
                                        <TextBlock Text="1" Foreground="White" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="Analyser l'espace disque" FontSize="16" FontWeight="SemiBold" Foreground="$textPrimary" Margin="10,0,0,0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Lancez d'abord une analyse pour identifier les fichiers nettoyables et obtenir des recommandations personnalisees."
                                           Foreground="$textSecondary" TextWrapping="Wrap" Margin="38,0,0,15"/>
                                <Button x:Name="btnAnalyzeForCleanup" Content="Analyser mon profil" Style="{StaticResource ModernButton}" HorizontalAlignment="Left" Margin="38,0,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- ETAPE 2: Resultats et conseils (cache au depart) -->
                        <Border x:Name="borderCleanupAnalysis" Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15" BorderBrush="$successColor" BorderThickness="1" Visibility="Collapsed">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Border Background="$successColor" Width="28" Height="28" CornerRadius="14">
                                        <TextBlock Text="2" Foreground="White" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="Resultat de l'analyse" FontSize="16" FontWeight="SemiBold" Foreground="$textPrimary" Margin="10,0,0,0" VerticalAlignment="Center"/>
                                </StackPanel>

                                <!-- Statistiques -->
                                <Border Background="$bgTertiary" Padding="15" CornerRadius="8" Margin="38,0,0,15">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <StackPanel Grid.Column="0" HorizontalAlignment="Center">
                                            <TextBlock x:Name="txtCleanupTotalSize" Text="--" FontSize="24" FontWeight="Bold" Foreground="$accentColor" HorizontalAlignment="Center"/>
                                            <TextBlock Text="Espace occupe" Foreground="$textSecondary" FontSize="11" HorizontalAlignment="Center"/>
                                        </StackPanel>
                                        <StackPanel Grid.Column="1" HorizontalAlignment="Center">
                                            <TextBlock x:Name="txtCleanupTotalFiles" Text="--" FontSize="24" FontWeight="Bold" Foreground="$accentColor" HorizontalAlignment="Center"/>
                                            <TextBlock Text="Fichiers" Foreground="$textSecondary" FontSize="11" HorizontalAlignment="Center"/>
                                        </StackPanel>
                                        <StackPanel Grid.Column="2" HorizontalAlignment="Center">
                                            <TextBlock x:Name="txtCleanupPotential" Text="--" FontSize="24" FontWeight="Bold" Foreground="$successColor" HorizontalAlignment="Center"/>
                                            <TextBlock Text="A recuperer" Foreground="$textSecondary" FontSize="11" HorizontalAlignment="Center"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <!-- Conseils -->
                                <TextBlock Text="💡 Conseils personnalises" FontWeight="SemiBold" Foreground="$textPrimary" Margin="38,0,0,8"/>
                                <Border Background="$bgPrimary" Padding="12" CornerRadius="6" Margin="38,0,0,0">
                                    <TextBlock x:Name="txtCleanupAdvice" Text="" Foreground="$textSecondary" TextWrapping="Wrap" FontSize="12"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- ETAPE 3: Options de nettoyage (cache au depart) -->
                        <Border x:Name="borderCleanupOptions" Background="$bgSecondary" Padding="20" CornerRadius="10" Margin="0,0,0,15" BorderBrush="$borderColor" BorderThickness="1" Visibility="Collapsed">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,15">
                                    <Border Background="$warningColor" Width="28" Height="28" CornerRadius="14">
                                        <TextBlock Text="3" Foreground="#1a1a1a" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <TextBlock Text="Selectionner les elements a nettoyer" FontSize="16" FontWeight="SemiBold" Foreground="$textPrimary" Margin="10,0,0,0" VerticalAlignment="Center"/>
                                </StackPanel>

                                <!-- Cache navigateurs -->
                                <TextBlock Text="Cache des Navigateurs" FontWeight="SemiBold" Foreground="$textPrimary" Margin="38,0,0,8"/>
                                <TextBlock Text="Conserve vos mots de passe et favoris" Foreground="$textMuted" FontSize="11" Margin="38,0,0,8"/>
                                <StackPanel Margin="48,0,0,15">
                                    <CheckBox x:Name="chkEdgeCache" Content="Microsoft Edge" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                    <CheckBox x:Name="chkFirefoxCache" Content="Mozilla Firefox" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                    <CheckBox x:Name="chkChromeCache" Content="Google Chrome" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                </StackPanel>

                                <!-- Fichiers temporaires utilisateur -->
                                <TextBlock Text="Fichiers temporaires" FontWeight="SemiBold" Foreground="$textPrimary" Margin="38,0,0,8"/>
                                <StackPanel Margin="48,0,0,15">
                                    <CheckBox x:Name="chkUserTemp" Content="Dossier Temp utilisateur" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                    <CheckBox x:Name="chkThumbnails" Content="Cache des miniatures" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                    <CheckBox x:Name="chkRecycleBin" Content="Corbeille" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                    <CheckBox x:Name="chkRecentDocs" Content="Documents recents" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                    <CheckBox x:Name="chkLogFiles" Content="Fichiers .log (+ de 30 jours)" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                </StackPanel>

                                <!-- Dossier Telechargements - avec avertissement -->
                                <Border Background="$warningColor" Padding="12" CornerRadius="6" Margin="38,0,0,15" Opacity="0.9">
                                    <StackPanel>
                                        <CheckBox x:Name="chkDownloads" Foreground="#1a1a1a" Margin="0,0,0,8">
                                            <CheckBox.Content>
                                                <TextBlock Text="📥 Dossier Telechargements" FontWeight="SemiBold" Foreground="#1a1a1a"/>
                                            </CheckBox.Content>
                                        </CheckBox>
                                        <TextBlock Text="Attention : Les fichiers supprimes ici sont generalement retelechargea­bles depuis leur source d'origine. Ce nettoyage est de VOTRE responsabilite. Verifiez le contenu avant de cocher cette option."
                                                   Foreground="#1a1a1a" TextWrapping="Wrap" FontSize="11" Margin="24,0,0,0"/>
                                        <TextBlock x:Name="txtDownloadsInfo" Text="" Foreground="#1a1a1a" FontWeight="SemiBold" FontSize="11" Margin="24,5,0,0"/>
                                    </StackPanel>
                                </Border>

                                <!-- Section Admin (visible uniquement en mode admin) -->
                                <Border x:Name="borderAdminSection" Visibility="Collapsed" Margin="0,10,0,0">
                                    <StackPanel>
                                        <Border Background="$dangerColor" Padding="8,5" CornerRadius="5" HorizontalAlignment="Left" Margin="38,0,0,10">
                                            <TextBlock Text="🔒 Options Administrateur" FontWeight="SemiBold" Foreground="White" FontSize="12"/>
                                        </Border>
                                        <StackPanel Margin="48,0,0,0">
                                            <CheckBox x:Name="chkWindowsTemp" Content="Temp Windows (C:\Windows\Temp)" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                            <CheckBox x:Name="chkPrefetch" Content="Prefetch" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                            <CheckBox x:Name="chkIconCache" Content="Cache des icones systeme" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                            <CheckBox x:Name="chkFontCache" Content="Cache des polices" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                            <CheckBox x:Name="chkCrashDumps" Content="Rapports d'erreurs Windows" Foreground="$textPrimary" Margin="0,0,0,5"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- Barre de progression -->
                        <Border x:Name="borderCleanupProgress" Background="$bgSecondary" Padding="15" CornerRadius="8" Margin="0,0,0,15" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock x:Name="txtCleanupProgress" Text="Nettoyage en cours..." Foreground="$textPrimary" FontWeight="SemiBold" Margin="0,0,0,8"/>
                                <ProgressBar x:Name="progressCleanup" Height="20" Minimum="0" Maximum="100" Value="0"
                                             Background="$bgTertiary" Foreground="$accentColor"/>
                                <TextBlock x:Name="txtCleanupCurrentItem" Text="" Foreground="$textSecondary" FontSize="11" Margin="0,8,0,0" TextTrimming="CharacterEllipsis"/>
                            </StackPanel>
                        </Border>

                        <!-- Boutons d'action (cache au depart) -->
                        <Border x:Name="borderCleanupActions" Background="$bgTertiary" Padding="20" CornerRadius="10" Margin="0,0,0,15" Visibility="Collapsed">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                    <TextBlock x:Name="txtCleanupEstimate" Text="Cliquez sur 'Estimer' pour calculer l'espace a liberer" Foreground="$textPrimary" FontWeight="SemiBold"/>
                                    <TextBlock x:Name="txtCleanupDetails" Text="" Foreground="$textSecondary" FontSize="12" TextWrapping="Wrap"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1" Orientation="Horizontal">
                                    <Button x:Name="btnEstimateCleanup" Content="Estimer" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/>
                                    <Button x:Name="btnRunCleanup" Content="Nettoyer" Style="{StaticResource SecondaryButton}" IsEnabled="False" Opacity="0.5"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Resultat du nettoyage -->
                        <Border x:Name="borderCleanupResult" Background="$bgSecondary" Padding="15" CornerRadius="8" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock x:Name="txtCleanupResult" Text="" Foreground="$successColor" FontWeight="SemiBold"/>
                                <TextBlock x:Name="txtCleanupResultDetails" Text="" Foreground="$textSecondary" TextWrapping="Wrap" Margin="0,5,0,0"/>
                                <TextBlock x:Name="txtEmailStatus" Text="" Foreground="$textMuted" FontSize="11" Margin="0,8,0,0"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- Onglet Journal -->
            <TabItem Header="Journal" Style="{StaticResource TabStyle}">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Button x:Name="btnClearLog" Content="Effacer le journal" Style="{StaticResource SecondaryButton}"
                            HorizontalAlignment="Left" Margin="0,0,0,10"/>

                    <TextBox x:Name="txtLog" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto" Background="$bgSecondary"
                             Foreground="$textPrimary" BorderBrush="$borderColor" Padding="10"
                             FontFamily="Consolas" FontSize="12"/>
                </Grid>
            </TabItem>
        </TabControl>

        <!-- Barre de statut -->
        <Border Grid.Row="2" Background="$bgSecondary" Padding="10,8" BorderBrush="$borderColor" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="txtStatus" Text="Pret" Foreground="$textPrimary" VerticalAlignment="Center"/>
                    <TextBlock x:Name="txtCurrentFolder" Text="" Foreground="$textSecondary" Margin="20,0,0,0" VerticalAlignment="Center"
                               MaxWidth="400" TextTrimming="CharacterEllipsis"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <TextBlock x:Name="txtProgress" Text="" Foreground="$textSecondary" VerticalAlignment="Center" Margin="0,0,15,0"/>
                    <ProgressBar x:Name="progressBar" Width="200" Height="18" Minimum="0" Maximum="100" Value="0"
                                 Background="$bgPrimary" Foreground="$accentColor" Visibility="Collapsed"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    # Parser le XAML
    $stringReader = New-Object System.IO.StringReader($xaml)
    $reader = [System.Xml.XmlReader]::Create($stringReader)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # Recuperer les controles
    $btnAnalyze = $window.FindName("btnAnalyze")
    $btnExport = $window.FindName("btnExport")
    $btnCancel = $window.FindName("btnCancel")
    $btnBrowse = $window.FindName("btnBrowse")
    $btnApplyFilters = $window.FindName("btnApplyFilters")
    $btnResetFilters = $window.FindName("btnResetFilters")
    $btnClearLog = $window.FindName("btnClearLog")
    $btnToggleTheme = $window.FindName("btnToggleTheme")
    $txtPath = $window.FindName("txtPath")
    $txtStatus = $window.FindName("txtStatus")
    $txtCurrentFolder = $window.FindName("txtCurrentFolder")
    $txtProgress = $window.FindName("txtProgress")
    $progressBar = $window.FindName("progressBar")
    $txtTotalSize = $window.FindName("txtTotalSize")
    $txtTotalFiles = $window.FindName("txtTotalFiles")
    $txtTotalFolders = $window.FindName("txtTotalFolders")
    $txtDuplicates = $window.FindName("txtDuplicates")
    $lstExtensions = $window.FindName("lstExtensions")
    $treeHierarchy = $window.FindName("treeHierarchy")
    $gridTop20 = $window.FindName("gridTop20")
    $lstDuplicates = $window.FindName("lstDuplicates")
    $txtDuplicatesInfo = $window.FindName("txtDuplicatesInfo")
    $txtLog = $window.FindName("txtLog")
    $chkTmp = $window.FindName("chkTmp")
    $chkLog = $window.FindName("chkLog")
    $chkBak = $window.FindName("chkBak")
    $chkCache = $window.FindName("chkCache")
    $chkOst = $window.FindName("chkOst")
    $chkPst = $window.FindName("chkPst")
    $chkAppData = $window.FindName("chkAppData")
    $txtMinSize = $window.FindName("txtMinSize")
    $txtOlderThan = $window.FindName("txtOlderThan")
    $txtCustomExtensions = $window.FindName("txtCustomExtensions")
    $txtCustomFolders = $window.FindName("txtCustomFolders")

    # Controles de l'onglet Nettoyage - Mode et infos
    $borderModeInfo = $window.FindName("borderModeInfo")
    $txtModeIcon = $window.FindName("txtModeIcon")
    $txtModeTitle = $window.FindName("txtModeTitle")
    $txtModeDesc = $window.FindName("txtModeDesc")
    $btnAnalyzeForCleanup = $window.FindName("btnAnalyzeForCleanup")

    # Controles de l'onglet Nettoyage - Analyse
    $borderCleanupAnalysis = $window.FindName("borderCleanupAnalysis")
    $txtCleanupTotalSize = $window.FindName("txtCleanupTotalSize")
    $txtCleanupTotalFiles = $window.FindName("txtCleanupTotalFiles")
    $txtCleanupPotential = $window.FindName("txtCleanupPotential")
    $txtCleanupAdvice = $window.FindName("txtCleanupAdvice")

    # Controles de l'onglet Nettoyage - Options
    $borderCleanupOptions = $window.FindName("borderCleanupOptions")
    $chkEdgeCache = $window.FindName("chkEdgeCache")
    $chkFirefoxCache = $window.FindName("chkFirefoxCache")
    $chkChromeCache = $window.FindName("chkChromeCache")
    $chkUserTemp = $window.FindName("chkUserTemp")
    $chkThumbnails = $window.FindName("chkThumbnails")
    $chkRecycleBin = $window.FindName("chkRecycleBin")
    $chkRecentDocs = $window.FindName("chkRecentDocs")
    $chkLogFiles = $window.FindName("chkLogFiles")
    $chkDownloads = $window.FindName("chkDownloads")
    $txtDownloadsInfo = $window.FindName("txtDownloadsInfo")

    # Controles de l'onglet Nettoyage - Section Admin
    $borderAdminSection = $window.FindName("borderAdminSection")
    $chkWindowsTemp = $window.FindName("chkWindowsTemp")
    $chkPrefetch = $window.FindName("chkPrefetch")
    $chkIconCache = $window.FindName("chkIconCache")
    $chkFontCache = $window.FindName("chkFontCache")
    $chkCrashDumps = $window.FindName("chkCrashDumps")

    # Controles de l'onglet Nettoyage - Actions
    $borderCleanupActions = $window.FindName("borderCleanupActions")
    $btnEstimateCleanup = $window.FindName("btnEstimateCleanup")
    $btnRunCleanup = $window.FindName("btnRunCleanup")
    $txtCleanupEstimate = $window.FindName("txtCleanupEstimate")
    $txtCleanupDetails = $window.FindName("txtCleanupDetails")
    $borderCleanupResult = $window.FindName("borderCleanupResult")
    $txtCleanupResult = $window.FindName("txtCleanupResult")
    $txtCleanupResultDetails = $window.FindName("txtCleanupResultDetails")
    $txtEmailStatus = $window.FindName("txtEmailStatus")
    $borderCleanupProgress = $window.FindName("borderCleanupProgress")
    $txtCleanupProgress = $window.FindName("txtCleanupProgress")
    $progressCleanup = $window.FindName("progressCleanup")
    $txtCleanupCurrentItem = $window.FindName("txtCleanupCurrentItem")

    # Variable pour stocker le resultat de l'estimation
    $Script:CleanupEstimated = $false
    $Script:EstimatedFileCount = 0
    $Script:CleanupAnalyzed = $false

    # Configurer le mode utilisateur/admin
    if ($Script:IsAdmin) {
        $borderModeInfo.Background = [System.Windows.Media.Brushes]::Green
        $txtModeIcon.Text = "🔒"
        $txtModeTitle.Text = "Mode Administrateur"
        $txtModeDesc.Text = "Acces complet - Tous les nettoyages disponibles"
        $borderAdminSection.Visibility = "Visible"
    } else {
        $txtModeIcon.Text = "👤"
        $txtModeTitle.Text = "Mode Utilisateur"
        $txtModeDesc.Text = "Analyse limitee a votre profil utilisateur"
        $borderAdminSection.Visibility = "Collapsed"
    }

    # Fonction pour ajouter au journal
    $addLog = {
        param([string]$message)
        $timestamp = Get-Date -Format "HH:mm:ss"
        $txtLog.Dispatcher.Invoke([Action]{
            $txtLog.AppendText("[$timestamp] $message`r`n")
            $txtLog.ScrollToEnd()
        })
    }

    # Fonction pour obtenir les filtres
    $getFilters = {
        $filters = @{
            ExcludedExtensions = @()
            ExcludedFolders = @()
            MinSize = 0
            OlderThan = $null
            SelectedSubfolders = @()
        }

        if ($chkTmp.IsChecked) { $filters.ExcludedExtensions += '.tmp' }
        if ($chkLog.IsChecked) { $filters.ExcludedExtensions += '.log' }
        if ($chkBak.IsChecked) { $filters.ExcludedExtensions += '.bak' }
        if ($chkCache.IsChecked) { $filters.ExcludedExtensions += '.cache' }
        if ($chkOst.IsChecked) { $filters.ExcludedExtensions += '.ost' }
        if ($chkPst.IsChecked) { $filters.ExcludedExtensions += '.pst' }

        if ($txtCustomExtensions.Text) {
            $custom = $txtCustomExtensions.Text -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
            $filters.ExcludedExtensions += $custom
        }

        if ($chkAppData.IsChecked) { $filters.ExcludedFolders += 'AppData\Local\Temp' }

        if ($txtCustomFolders.Text) {
            $custom = $txtCustomFolders.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            $filters.ExcludedFolders += $custom
        }

        $minSize = 0
        if ([int]::TryParse($txtMinSize.Text, [ref]$minSize) -and $minSize -gt 0) {
            $filters.MinSize = $minSize * 1MB
        }

        $olderThan = 0
        if ([int]::TryParse($txtOlderThan.Text, [ref]$olderThan) -and $olderThan -gt 0) {
            $filters.OlderThan = (Get-Date).AddDays(-$olderThan)
        }

        # Sous-dossiers utilisateur selectionnes
        if ($chkDocuments.IsChecked) { $filters.SelectedSubfolders += 'Documents' }
        if ($chkDesktop.IsChecked) { $filters.SelectedSubfolders += 'Desktop' }
        if ($chkDownloads.IsChecked) { $filters.SelectedSubfolders += 'Downloads' }
        if ($chkPictures.IsChecked) { $filters.SelectedSubfolders += 'Pictures' }
        if ($chkVideos.IsChecked) { $filters.SelectedSubfolders += 'Videos' }
        if ($chkMusic.IsChecked) { $filters.SelectedSubfolders += 'Music' }
        if ($chkAppDataLocal.IsChecked) { $filters.SelectedSubfolders += 'AppData\Local' }
        if ($chkAppDataRoaming.IsChecked) { $filters.SelectedSubfolders += 'AppData\Roaming' }
        if ($chkOneDrive.IsChecked) { $filters.SelectedSubfolders += 'OneDrive' }

        return $filters
    }

    # Fonction pour mettre a jour l'UI avec les resultats
    $updateUI = {
        param([PSCustomObject]$results)

        $txtTotalSize.Text = $results.TotalSizeFormatted
        $txtTotalFiles.Text = $results.TotalFiles.ToString('N0')
        $txtTotalFolders.Text = $results.TotalFolders.ToString('N0')
        $txtDuplicates.Text = $results.Duplicates.Count.ToString()

        # Top 5 extensions
        $maxSize = 0
        foreach ($val in $results.ExtensionStats.Values) {
            if ($val.Size -gt $maxSize) { $maxSize = $val.Size }
        }
        $top5 = $results.ExtensionStats.GetEnumerator() |
            Sort-Object { $_.Value.Size } -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                [PSCustomObject]@{
                    Extension = $_.Key
                    SizeFormatted = Format-FileSize -Bytes $_.Value.Size
                    Percent = if ($maxSize -gt 0) { ($_.Value.Size / $maxSize) * 100 } else { 0 }
                }
            }
        $lstExtensions.ItemsSource = $top5

        # Hierarchie
        $treeHierarchy.ItemsSource = @($results.RootNode)

        # Top 20
        $gridTop20.ItemsSource = $results.Top20Files

        # Doublons
        $lstDuplicates.ItemsSource = $results.Duplicates
        $totalWasted = ($results.Duplicates | Measure-Object -Property WastedSpace -Sum).Sum
        if ($null -eq $totalWasted) { $totalWasted = 0 }
        $txtDuplicatesInfo.Text = "$($results.Duplicates.Count) groupes de doublons detectes - Espace gaspille: $(Format-FileSize -Bytes $totalWasted)"
    }

    # Fonction pour obtenir les chemins de nettoyage selon les options cochees
    $getCleanupPaths = {
        $paths = New-Object System.Collections.ArrayList

        # Cache Edge Chromium (conserve mots de passe et favoris)
        if ($chkEdgeCache.IsChecked) {
            $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
            @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage", "Service Worker\ScriptCache") | ForEach-Object {
                $p = Join-Path $edgePath $_
                if (Test-Path $p) { [void]$paths.Add(@{ Path = $p; Category = "Edge"; Name = $_ }) }
            }
        }

        # Cache Firefox (conserve mots de passe et favoris)
        if ($chkFirefoxCache.IsChecked) {
            $firefoxPath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
            if (Test-Path $firefoxPath) {
                Get-ChildItem $firefoxPath -Directory | ForEach-Object {
                    $profilePath = $_.FullName
                    @("cache2", "startupCache", "thumbnails") | ForEach-Object {
                        $p = Join-Path $profilePath $_
                        if (Test-Path $p) { [void]$paths.Add(@{ Path = $p; Category = "Firefox"; Name = $_ }) }
                    }
                }
            }
        }

        # Cache Chrome (conserve mots de passe et favoris)
        if ($chkChromeCache.IsChecked) {
            $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
            @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage", "Service Worker\ScriptCache") | ForEach-Object {
                $p = Join-Path $chromePath $_
                if (Test-Path $p) { [void]$paths.Add(@{ Path = $p; Category = "Chrome"; Name = $_ }) }
            }
        }

        # Temp utilisateur
        if ($chkUserTemp.IsChecked) {
            $tempPath = $env:TEMP
            if (Test-Path $tempPath) { [void]$paths.Add(@{ Path = $tempPath; Category = "Windows"; Name = "Temp utilisateur" }) }
        }

        # Temp Windows
        if ($chkWindowsTemp.IsChecked) {
            $winTemp = "C:\Windows\Temp"
            if (Test-Path $winTemp) { [void]$paths.Add(@{ Path = $winTemp; Category = "Windows"; Name = "Temp Windows" }) }
        }

        # Prefetch
        if ($chkPrefetch.IsChecked) {
            $prefetch = "C:\Windows\Prefetch"
            if (Test-Path $prefetch) { [void]$paths.Add(@{ Path = $prefetch; Category = "Windows"; Name = "Prefetch" }) }
        }

        # Cache miniatures
        if ($chkThumbnails.IsChecked) {
            $thumbs = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
            if (Test-Path $thumbs) { [void]$paths.Add(@{ Path = $thumbs; Category = "Cache"; Name = "Miniatures"; Pattern = "thumbcache_*.db" }) }
        }

        # Cache icones
        if ($chkIconCache.IsChecked) {
            $iconCache = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db"
            [void]$paths.Add(@{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Category = "Cache"; Name = "Icones"; Pattern = "iconcache_*.db" })
        }

        # Cache polices
        if ($chkFontCache.IsChecked) {
            $fontCache = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache"
            if (Test-Path $fontCache) { [void]$paths.Add(@{ Path = $fontCache; Category = "Cache"; Name = "Polices" }) }
        }

        # Documents recents
        if ($chkRecentDocs.IsChecked) {
            $recent = "$env:APPDATA\Microsoft\Windows\Recent"
            if (Test-Path $recent) { [void]$paths.Add(@{ Path = $recent; Category = "Historique"; Name = "Documents recents" }) }
        }

        # Fichiers log anciens
        if ($chkLogFiles.IsChecked) {
            [void]$paths.Add(@{ Path = $env:USERPROFILE; Category = "Logs"; Name = "Fichiers log anciens"; Pattern = "*.log"; MaxAge = 30 })
        }

        # Rapports d'erreurs
        if ($chkCrashDumps.IsChecked) {
            $wer = "$env:LOCALAPPDATA\CrashDumps"
            if (Test-Path $wer) { [void]$paths.Add(@{ Path = $wer; Category = "Erreurs"; Name = "Crash dumps" }) }
            $werReports = "$env:LOCALAPPDATA\Microsoft\Windows\WER"
            if (Test-Path $werReports) { [void]$paths.Add(@{ Path = $werReports; Category = "Erreurs"; Name = "Rapports WER" }) }
        }

        # Dossier Telechargements (sous responsabilite utilisateur)
        if ($chkDownloads.IsChecked) {
            $downloadsPath = Get-DownloadsPath
            if (Test-Path $downloadsPath) {
                [void]$paths.Add(@{ Path = $downloadsPath; Category = "Telechargements"; Name = "Dossier Downloads" })
            }
        }

        return $paths
    }

    # Fonction pour estimer l'espace a liberer
    $estimateCleanup = {
        $paths = & $getCleanupPaths
        $totalSize = 0
        $totalFiles = 0
        $details = New-Object System.Collections.ArrayList

        foreach ($item in $paths) {
            $size = 0
            $fileCount = 0
            try {
                if ($item.Pattern) {
                    if ($item.MaxAge) {
                        $cutoffDate = (Get-Date).AddDays(-$item.MaxAge)
                        $files = Get-ChildItem -Path $item.Path -Filter $item.Pattern -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }
                    } else {
                        $files = Get-ChildItem -Path $item.Path -Filter $item.Pattern -File -ErrorAction SilentlyContinue
                    }
                    if ($files) {
                        $measure = $files | Measure-Object -Property Length -Sum
                        $size = $measure.Sum
                        $fileCount = $measure.Count
                    }
                } else {
                    $files = Get-ChildItem -Path $item.Path -Recurse -File -ErrorAction SilentlyContinue
                    if ($files) {
                        $measure = $files | Measure-Object -Property Length -Sum
                        $size = $measure.Sum
                        $fileCount = $measure.Count
                    }
                }
            } catch {
                # Ignorer les erreurs d'acces
            }
            if ($null -eq $size) { $size = 0 }
            if ($null -eq $fileCount) { $fileCount = 0 }
            $totalSize += $size
            $totalFiles += $fileCount
            if ($size -gt 0) {
                [void]$details.Add("$($item.Category)/$($item.Name): $(Format-FileSize -Bytes $size) ($fileCount fichiers)")
            }
        }

        return @{
            TotalSize = $totalSize
            TotalSizeFormatted = Format-FileSize -Bytes $totalSize
            TotalFiles = $totalFiles
            Details = $details
        }
    }

    # Fonction pour effectuer le nettoyage avec progression
    $runCleanup = {
        param([scriptblock]$ProgressCallback)

        $paths = & $getCleanupPaths
        $totalFreed = 0
        $filesDeleted = 0
        $errors = New-Object System.Collections.ArrayList
        $totalItems = $paths.Count
        $currentItem = 0

        # Vider la corbeille si demande
        if ($chkRecycleBin.IsChecked) {
            $currentItem++
            if ($ProgressCallback) {
                & $ProgressCallback "Vidage de la corbeille..." $currentItem $totalItems
            }
            try {
                $shell = New-Object -ComObject Shell.Application
                $recycleBin = $shell.Namespace(0xA)
                $recycleCount = $recycleBin.Items().Count
                if ($recycleCount -gt 0) {
                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    & $addLog "Corbeille videe ($recycleCount elements)"
                }
            } catch {
                [void]$errors.Add("Corbeille: $($_.Exception.Message)")
            }
        }

        foreach ($item in $paths) {
            $currentItem++
            $itemName = "$($item.Category)/$($item.Name)"

            if ($ProgressCallback) {
                & $ProgressCallback "Nettoyage: $itemName" $currentItem $totalItems
            }

            try {
                if ($item.Pattern) {
                    if ($item.MaxAge) {
                        $cutoffDate = (Get-Date).AddDays(-$item.MaxAge)
                        $files = Get-ChildItem -Path $item.Path -Filter $item.Pattern -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }
                    } else {
                        $files = Get-ChildItem -Path $item.Path -Filter $item.Pattern -File -ErrorAction SilentlyContinue
                    }
                    foreach ($file in $files) {
                        try {
                            $totalFreed += $file.Length
                            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                            $filesDeleted++
                        } catch {
                            [void]$errors.Add("$($file.Name): $($_.Exception.Message)")
                        }
                    }
                } else {
                    $files = Get-ChildItem -Path $item.Path -Recurse -File -ErrorAction SilentlyContinue
                    $fileIndex = 0
                    $totalFilesInPath = @($files).Count
                    foreach ($file in $files) {
                        $fileIndex++
                        # Mise a jour periodique pour ne pas bloquer l'UI
                        if ($fileIndex % 50 -eq 0 -and $ProgressCallback) {
                            & $ProgressCallback "Nettoyage: $itemName ($fileIndex/$totalFilesInPath fichiers)" $currentItem $totalItems
                        }
                        try {
                            $totalFreed += $file.Length
                            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                            $filesDeleted++
                        } catch {
                            [void]$errors.Add("$($file.Name): $($_.Exception.Message)")
                        }
                    }
                }
                & $addLog "Nettoye: $itemName"
            } catch {
                [void]$errors.Add("$($item.Name): $($_.Exception.Message)")
                & $addLog "Erreur nettoyage $($item.Name): $($_.Exception.Message)"
            }
        }

        return @{
            TotalFreed = $totalFreed
            TotalFreedFormatted = Format-FileSize -Bytes $totalFreed
            FilesDeleted = $filesDeleted
            Errors = $errors
        }
    }

    # Event: Parcourir
    $btnBrowse.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Selectionnez le dossier a analyser"
        $dialog.SelectedPath = $txtPath.Text
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtPath.Text = $dialog.SelectedPath
        }
    })

    # Event: Analyser
    $btnAnalyze.Add_Click({
        $path = $txtPath.Text
        if (-not (Test-Path $path)) {
            [System.Windows.MessageBox]::Show("Le chemin specifie n'existe pas.", "Erreur", "OK", "Error")
            return
        }

        $btnAnalyze.IsEnabled = $false
        $btnExport.IsEnabled = $false
        $btnCancel.IsEnabled = $true
        $progressBar.Visibility = "Visible"
        $progressBar.Value = 0
        $txtStatus.Text = "Analyse en cours..."

        & $addLog "Debut de l'analyse: $path"

        $filters = & $getFilters

        # Verifier si on est en mode sous-dossiers
        $isUserProfile = ($path -eq $env:USERPROFILE) -or ($path -eq [Environment]::GetFolderPath('UserProfile'))
        if ($isUserProfile -and $filters.SelectedSubfolders.Count -gt 0) {
            & $addLog "Mode sous-dossiers: $($filters.SelectedSubfolders.Count) sous-dossiers selectionnes"
            foreach ($sf in $filters.SelectedSubfolders) {
                & $addLog "  - $sf"
            }
        }
        if ($filters.ExcludedExtensions.Count -gt 0) {
            & $addLog "Extensions exclues: $($filters.ExcludedExtensions -join ', ')"
        }

        try {
            $results = Start-Analysis -RootPath $path -ProgressCallback {
                param($currentFolder, $filesScanned)
                $window.Dispatcher.Invoke([Action]{
                    $txtCurrentFolder.Text = $currentFolder
                    $txtProgress.Text = "$filesScanned fichiers"
                }, [System.Windows.Threading.DispatcherPriority]::Background)
            } -Filters $filters

            $Script:AnalysisResults = $results
            & $updateUI $results

            $txtStatus.Text = "Analyse terminee"
            & $addLog "Analyse terminee: $($results.TotalFiles) fichiers, $($results.TotalSizeFormatted)"
            & $addLog "$($results.Duplicates.Count) groupes de doublons detectes"
            & $addLog "$($results.Errors.Count) erreurs rencontrees"

            foreach ($err in $results.Errors | Select-Object -First 10) {
                & $addLog "  - $err"
            }
            if ($results.Errors.Count -gt 10) {
                & $addLog "  ... et $($results.Errors.Count - 10) autres erreurs"
            }

        } catch {
            $txtStatus.Text = "Erreur"
            & $addLog "Erreur: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Erreur lors de l'analyse: $($_.Exception.Message)", "Erreur", "OK", "Error")
        } finally {
            $progressBar.Visibility = "Collapsed"
            $btnAnalyze.IsEnabled = $true
            $btnExport.IsEnabled = ($null -ne $Script:AnalysisResults)
            $btnCancel.IsEnabled = $false
        }
    })

    # Event: Annuler
    $btnCancel.Add_Click({
        $Script:CancelRequested = $true
        $txtStatus.Text = "Annulation..."
        & $addLog "Annulation demandee par l'utilisateur"
    })

    # Event: Exporter HTML
    $btnExport.Add_Click({
        if ($null -eq $Script:AnalysisResults) {
            [System.Windows.MessageBox]::Show("Veuillez d'abord effectuer une analyse.", "Information", "OK", "Information")
            return
        }

        $txtStatus.Text = "Generation du rapport..."
        & $addLog "Generation du rapport HTML..."

        try {
            $html = Generate-HTMLReport -Results $Script:AnalysisResults
            $fileName = "DiskAnalysis_$($env:USERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            $filePath = Join-Path $ExportPath $fileName

            $html | Out-File -FilePath $filePath -Encoding UTF8

            & $addLog "Rapport genere: $filePath"
            $txtStatus.Text = "Rapport exporte"

            Start-Process $filePath

            [System.Windows.MessageBox]::Show("Rapport genere avec succes:`n$filePath", "Export reussi", "OK", "Information")

        } catch {
            & $addLog "Erreur export: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Erreur lors de l'export: $($_.Exception.Message)", "Erreur", "OK", "Error")
        }
    })

    # Event: Appliquer filtres
    $btnApplyFilters.Add_Click({
        $btnAnalyze.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    })

    # Event: Reinitialiser filtres
    $btnResetFilters.Add_Click({
        $chkTmp.IsChecked = $true
        $chkLog.IsChecked = $true
        $chkBak.IsChecked = $true
        $chkCache.IsChecked = $true
        $chkOst.IsChecked = $true
        $chkPst.IsChecked = $true
        $chkAppData.IsChecked = $true
        $txtMinSize.Text = "0"
        $txtOlderThan.Text = "0"
        $txtCustomExtensions.Text = ""
        $txtCustomFolders.Text = ""
        # Sous-dossiers
        $chkDocuments.IsChecked = $true
        $chkDesktop.IsChecked = $true
        $chkDownloads.IsChecked = $true
        $chkPictures.IsChecked = $true
        $chkVideos.IsChecked = $true
        $chkMusic.IsChecked = $true
        $chkAppDataLocal.IsChecked = $true
        $chkAppDataRoaming.IsChecked = $true
        $chkOneDrive.IsChecked = $true
        & $addLog "Filtres reinitialises"
    })

    # Event: Tout selectionner sous-dossiers
    $btnSelectAllFolders.Add_Click({
        $chkDocuments.IsChecked = $true
        $chkDesktop.IsChecked = $true
        $chkDownloads.IsChecked = $true
        $chkPictures.IsChecked = $true
        $chkVideos.IsChecked = $true
        $chkMusic.IsChecked = $true
        $chkAppDataLocal.IsChecked = $true
        $chkAppDataRoaming.IsChecked = $true
        $chkOneDrive.IsChecked = $true
    })

    # Event: Tout deselectionner sous-dossiers
    $btnDeselectAllFolders.Add_Click({
        $chkDocuments.IsChecked = $false
        $chkDesktop.IsChecked = $false
        $chkDownloads.IsChecked = $false
        $chkPictures.IsChecked = $false
        $chkVideos.IsChecked = $false
        $chkMusic.IsChecked = $false
        $chkAppDataLocal.IsChecked = $false
        $chkAppDataRoaming.IsChecked = $false
        $chkOneDrive.IsChecked = $false
    })

    # Event: Effacer journal
    $btnClearLog.Add_Click({
        $txtLog.Clear()
    })

    # Event: Analyser pour nettoyage (nouveau parcours)
    $btnAnalyzeForCleanup.Add_Click({
        $btnAnalyzeForCleanup.IsEnabled = $false
        $btnAnalyzeForCleanup.Content = "Analyse en cours..."

        & $addLog "Analyse du profil pour nettoyage..."

        # Force UI refresh
        $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        try {
            # Analyser le profil utilisateur
            $analysisPath = $env:USERPROFILE
            $totalSize = 0
            $totalFiles = 0

            # Calculer l'espace occupe
            $files = Get-ChildItem -Path $analysisPath -Recurse -File -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $totalSize += $file.Length
                $totalFiles++
            }

            # Calculer l'espace potentiellement recuperable
            $potentialSize = 0
            $potentialFiles = 0

            # Verifier les caches navigateurs
            $browserPaths = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
            )
            foreach ($bp in $browserPaths) {
                if (Test-Path $bp) {
                    $bFiles = Get-ChildItem -Path $bp -Recurse -File -ErrorAction SilentlyContinue
                    foreach ($bf in $bFiles) {
                        $potentialSize += $bf.Length
                        $potentialFiles++
                    }
                }
            }

            # Verifier le dossier Temp
            $tempPath = $env:TEMP
            if (Test-Path $tempPath) {
                $tFiles = Get-ChildItem -Path $tempPath -Recurse -File -ErrorAction SilentlyContinue
                foreach ($tf in $tFiles) {
                    $potentialSize += $tf.Length
                    $potentialFiles++
                }
            }

            # Verifier le dossier Telechargements
            $downloadsPath = Get-DownloadsPath
            $downloadsSize = 0
            $downloadsFiles = 0
            if (Test-Path $downloadsPath) {
                $dFiles = Get-ChildItem -Path $downloadsPath -Recurse -File -ErrorAction SilentlyContinue
                foreach ($df in $dFiles) {
                    $downloadsSize += $df.Length
                    $downloadsFiles++
                }
            }

            # Mettre a jour l'interface
            $txtCleanupTotalSize.Text = Format-FileSize -Bytes $totalSize
            $txtCleanupTotalFiles.Text = $totalFiles.ToString('N0')
            $txtCleanupPotential.Text = Format-FileSize -Bytes $potentialSize

            # Generer les conseils
            $advice = New-Object System.Text.StringBuilder

            if ($potentialSize -gt 500MB) {
                [void]$advice.AppendLine("• Vos caches navigateurs et fichiers temporaires occupent beaucoup d'espace. Un nettoyage est recommande.")
            } elseif ($potentialSize -gt 100MB) {
                [void]$advice.AppendLine("• Quelques fichiers temporaires peuvent etre nettoyes pour gagner de l'espace.")
            } else {
                [void]$advice.AppendLine("• Votre profil est relativement propre. Peu de fichiers a nettoyer.")
            }

            if ($downloadsSize -gt 1GB) {
                [void]$advice.AppendLine("• Votre dossier Telechargements contient $(Format-FileSize -Bytes $downloadsSize) ($downloadsFiles fichiers). Pensez a archiver ou supprimer les fichiers inutiles.")
                $txtDownloadsInfo.Text = "Contient actuellement $(Format-FileSize -Bytes $downloadsSize) ($downloadsFiles fichiers)"
            } elseif ($downloadsSize -gt 100MB) {
                [void]$advice.AppendLine("• Dossier Telechargements : $(Format-FileSize -Bytes $downloadsSize) - verifiez son contenu.")
                $txtDownloadsInfo.Text = "Contient $(Format-FileSize -Bytes $downloadsSize) ($downloadsFiles fichiers)"
            } else {
                $txtDownloadsInfo.Text = "Contient $(Format-FileSize -Bytes $downloadsSize)"
            }

            [void]$advice.AppendLine("• Les mots de passe et favoris de vos navigateurs seront preserves lors du nettoyage.")

            $txtCleanupAdvice.Text = $advice.ToString().TrimEnd()

            # Afficher les sections suivantes
            $borderCleanupAnalysis.Visibility = "Visible"
            $borderCleanupOptions.Visibility = "Visible"
            $borderCleanupActions.Visibility = "Visible"
            $Script:CleanupAnalyzed = $true

            & $addLog "Analyse terminee: $(Format-FileSize -Bytes $totalSize) occupes, $(Format-FileSize -Bytes $potentialSize) recuperables"

        } catch {
            [System.Windows.MessageBox]::Show("Erreur lors de l'analyse: $($_.Exception.Message)", "Erreur", "OK", "Error")
            & $addLog "Erreur analyse: $($_.Exception.Message)"
        } finally {
            $btnAnalyzeForCleanup.IsEnabled = $true
            $btnAnalyzeForCleanup.Content = "Analyser mon profil"
        }
    })

    # Event: Estimer nettoyage
    $btnEstimateCleanup.Add_Click({
        # Verifier qu'au moins une option est cochee
        $anyChecked = $chkEdgeCache.IsChecked -or $chkFirefoxCache.IsChecked -or $chkChromeCache.IsChecked -or
                      $chkUserTemp.IsChecked -or $chkWindowsTemp.IsChecked -or $chkPrefetch.IsChecked -or
                      $chkThumbnails.IsChecked -or $chkIconCache.IsChecked -or $chkFontCache.IsChecked -or
                      $chkRecycleBin.IsChecked -or $chkRecentDocs.IsChecked -or $chkLogFiles.IsChecked -or
                      $chkCrashDumps.IsChecked -or $chkDownloads.IsChecked

        if (-not $anyChecked) {
            [System.Windows.MessageBox]::Show("Veuillez selectionner au moins une option de nettoyage.", "Information", "OK", "Information")
            return
        }

        $txtCleanupEstimate.Text = "Estimation en cours, veuillez patienter..."
        $txtCleanupDetails.Text = "Analyse des fichiers..."
        $borderCleanupResult.Visibility = "Collapsed"
        $btnEstimateCleanup.IsEnabled = $false
        $btnRunCleanup.IsEnabled = $false
        $btnRunCleanup.Opacity = 0.5

        # Desactiver le bouton Nettoyer pendant l'estimation
        $Script:CleanupEstimated = $false

        & $addLog "Estimation du nettoyage..."

        # Force UI refresh
        $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        try {
            $estimate = & $estimateCleanup

            $Script:EstimatedFileCount = $estimate.TotalFiles
            $Script:CleanupEstimated = $true

            if ($estimate.TotalFiles -gt 0) {
                $txtCleanupEstimate.Text = "Espace a liberer: $($estimate.TotalSizeFormatted) ($($estimate.TotalFiles) fichiers)"
                $txtCleanupDetails.Text = ($estimate.Details -join "`n")

                # Activer le bouton Nettoyer avec style DangerButton
                $btnRunCleanup.IsEnabled = $true
                $btnRunCleanup.Opacity = 1
                $btnRunCleanup.Style = $window.FindResource("DangerButton")

                & $addLog "Estimation terminee: $($estimate.TotalSizeFormatted) ($($estimate.TotalFiles) fichiers)"
            } else {
                $txtCleanupEstimate.Text = "Aucun fichier a nettoyer"
                $txtCleanupDetails.Text = "Les emplacements selectionnes sont deja vides ou inaccessibles."
                $btnRunCleanup.IsEnabled = $false
                $btnRunCleanup.Opacity = 0.5
                & $addLog "Estimation terminee: aucun fichier a nettoyer"
            }
        } catch {
            $txtCleanupEstimate.Text = "Erreur lors de l'estimation"
            $txtCleanupDetails.Text = $_.Exception.Message
            $btnRunCleanup.IsEnabled = $false
            $btnRunCleanup.Opacity = 0.5
            & $addLog "Erreur estimation: $($_.Exception.Message)"
        } finally {
            $btnEstimateCleanup.IsEnabled = $true
        }
    })

    # Event: Lancer nettoyage
    $btnRunCleanup.Add_Click({
        # Verifier que l'estimation a ete faite
        if (-not $Script:CleanupEstimated) {
            [System.Windows.MessageBox]::Show("Veuillez d'abord cliquer sur 'Estimer' pour calculer l'espace a liberer.", "Information", "OK", "Information")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Etes-vous sur de vouloir supprimer definitivement $($Script:EstimatedFileCount) fichiers?`n`nCette action est irreversible.",
            "Confirmation",
            "YesNo",
            "Warning"
        )

        if ($result -ne "Yes") { return }

        # Afficher la barre de progression
        $borderCleanupProgress.Visibility = "Visible"
        $borderCleanupResult.Visibility = "Collapsed"
        $progressCleanup.Value = 0
        $txtCleanupProgress.Text = "Preparation du nettoyage..."
        $txtCleanupCurrentItem.Text = ""

        $txtCleanupEstimate.Text = "Nettoyage en cours..."
        $txtCleanupDetails.Text = "Ne fermez pas la fenetre"
        $btnRunCleanup.IsEnabled = $false
        $btnEstimateCleanup.IsEnabled = $false

        & $addLog "Debut du nettoyage..."

        # Force UI refresh
        $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        try {
            # Callback pour mise a jour de la progression
            $progressCallback = {
                param([string]$currentTask, [int]$current, [int]$total)
                $window.Dispatcher.Invoke([Action]{
                    $percent = if ($total -gt 0) { [math]::Round(($current / $total) * 100) } else { 0 }
                    $progressCleanup.Value = $percent
                    $txtCleanupProgress.Text = "Nettoyage en cours... ($percent%)"
                    $txtCleanupCurrentItem.Text = $currentTask
                }, [System.Windows.Threading.DispatcherPriority]::Background)
            }

            $cleanupResult = & $runCleanup -ProgressCallback $progressCallback

            # Masquer la progression et afficher le resultat
            $borderCleanupProgress.Visibility = "Collapsed"
            $borderCleanupResult.Visibility = "Visible"
            $txtCleanupResult.Text = "Nettoyage termine avec succes!"
            $txtCleanupResultDetails.Text = "$($cleanupResult.FilesDeleted) fichiers supprimes - $($cleanupResult.TotalFreedFormatted) liberes"

            if ($cleanupResult.Errors.Count -gt 0) {
                $txtCleanupResultDetails.Text += "`n$($cleanupResult.Errors.Count) fichiers n'ont pas pu etre supprimes (en cours d'utilisation)"
            }

            & $addLog "Nettoyage termine: $($cleanupResult.FilesDeleted) fichiers, $($cleanupResult.TotalFreedFormatted) liberes"

            # Envoyer le rapport par email
            $txtEmailStatus.Text = "Envoi du rapport par email..."
            $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

            $cleanupSummary = @"
Fichiers supprimes: $($cleanupResult.FilesDeleted)
Espace libere: $($cleanupResult.TotalFreedFormatted)
Erreurs: $($cleanupResult.Errors.Count)
"@
            $logContent = $txtLog.Text

            $emailResult = Send-CleanupReport -LogContent $logContent -CleanupSummary $cleanupSummary

            if ($emailResult.Success) {
                $txtEmailStatus.Text = "✓ $($emailResult.Message)"
                & $addLog $emailResult.Message
            } else {
                $txtEmailStatus.Text = "⚠ $($emailResult.Message)"
                & $addLog $emailResult.Message
            }

            # Reinitialiser l'etat
            $txtCleanupEstimate.Text = "Cliquez sur 'Estimer' pour calculer l'espace a liberer"
            $txtCleanupDetails.Text = ""
            $Script:CleanupEstimated = $false
            $btnRunCleanup.IsEnabled = $false
            $btnRunCleanup.Opacity = 0.5
            $btnRunCleanup.Style = $window.FindResource("SecondaryButton")

        } catch {
            $borderCleanupProgress.Visibility = "Collapsed"
            $borderCleanupResult.Visibility = "Visible"
            $txtCleanupResult.Text = "Erreur lors du nettoyage"
            $txtCleanupResultDetails.Text = $_.Exception.Message
            $txtEmailStatus.Text = ""
            & $addLog "Erreur nettoyage: $($_.Exception.Message)"
        } finally {
            $btnEstimateCleanup.IsEnabled = $true
        }
    })

    # Event: Changer de theme
    $btnToggleTheme.Add_Click({
        $currentTheme = Get-SystemTheme
        if ($currentTheme -eq "Dark") {
            $Script:ForcedTheme = "Light"
        } else {
            $Script:ForcedTheme = "Dark"
        }
        # Fermer et reouvrir la fenetre avec le nouveau theme
        $window.Close()
    })

    # Event: Double-clic sur Top 20 pour ouvrir
    $gridTop20.Add_MouseDoubleClick({
        $selected = $gridTop20.SelectedItem
        if ($selected) {
            Open-InExplorer -Path $selected.FullPath
        }
    })

    # Event: Double-clic sur hierarchie
    $treeHierarchy.Add_MouseDoubleClick({
        $selected = $treeHierarchy.SelectedItem
        if ($selected -and $selected.FullPath) {
            Open-InExplorer -Path $selected.FullPath
        }
    })

    # Raccourcis clavier
    $window.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq "F5") {
            $btnAnalyze.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
        elseif ($e.Key -eq "E" -and $e.KeyboardDevice.Modifiers -eq "Control") {
            $btnExport.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    })

    # Configuration selon les droits
    if (-not $Script:IsAdmin) {
        # En mode utilisateur, verrouiller le chemin et certains filtres
        $btnBrowse.IsEnabled = $false
        $btnBrowse.ToolTip = "Le chemin est verrouille en mode utilisateur"
        $txtPath.IsReadOnly = $true
        $txtPath.ToolTip = "Analyse limitee a votre profil utilisateur"

        # Desactiver les options admin dans les filtres
        if ($chkAppData) { $chkAppData.IsChecked = $false }

        & $addLog "Mode UTILISATEUR - Analyse limitee au profil"
    } else {
        & $addLog "Mode ADMINISTRATEUR - Acces complet"
    }

    # Journal initial
    & $addLog "Application demarree - v$($Script:Version)"
    & $addLog "Theme detecte: $theme"
    & $addLog "Chemin d'analyse: $AnalysisPath"
    & $addLog "Ordinateur: $env:COMPUTERNAME | Utilisateur: $env:USERNAME"

    # Afficher la fenetre
    [void]$window.ShowDialog()
}
#endregion

#region Point d'entree principal

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell 5.1 ou superieur est requis."
    exit 1
}

# Detecter les droits administrateur
$Script:IsAdmin = Test-IsAdmin

# En mode utilisateur, forcer le chemin vers le profil utilisateur
if (-not $Script:IsAdmin) {
    $Path = $env:USERPROFILE
    Write-Host "Mode utilisateur: analyse limitee au profil $Path" -ForegroundColor Cyan
} else {
    Write-Host "Mode administrateur: acces complet disponible" -ForegroundColor Green
}

if (-not (Test-Path $Path)) {
    Write-Error "Le chemin specifie n'existe pas: $Path"
    exit 1
}

# Boucle pour permettre le changement de theme
$previousTheme = $null
do {
    $currentTheme = Get-SystemTheme
    Show-MainWindow -AnalysisPath $Path
    # Si le theme a change, on reboucle pour reouvrir avec le nouveau theme
} while ($Script:ForcedTheme -ne $null -and $previousTheme -ne $Script:ForcedTheme -and ($previousTheme = $Script:ForcedTheme))

#endregion
