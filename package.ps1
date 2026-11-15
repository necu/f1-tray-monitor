# Empaqueta F1 Tray Monitor en un ZIP portable y comprueba su contenido.
#
#   .\package.ps1                 -> releases\F1-Tray-Monitor-<version>.zip + SHA256SUMS
#   .\package.ps1 -Verify         -> construye y valida en %TEMP% sin publicar nada
#   .\package.ps1 -Version 1.4.0  -> fuerza otra version
#
# Mantiene la lista de archivos y el config.json por defecto en un solo sitio
# para que el paquete sea reproducible desde cualquier copia del proyecto.
[CmdletBinding()]
param(
    [string]$Version = '',
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not $Version) {
    $line = Select-String -Path (Join-Path $root 'monitor.ps1') -Pattern "AppVersion\s*=\s*'([^']+)'" |
        Select-Object -First 1
    if (-not $line) { throw 'No se pudo leer AppVersion de monitor.ps1' }
    $Version = [regex]::Match($line.Line, "'([^']+)'").Groups[1].Value
}

$files = @(
    '.editorconfig',
    '.gitattributes',
    '.gitignore',
    'CHANGELOG.md',
    'check_monitor.ps1',
    'check_sources.ps1',
    'CODE_OF_CONDUCT.md',
    'CONTRIBUTING.md',
    'F1 Monitor.cmd',
    'f1.ico',
    'f1_scraper.ps1',
    'install-autostart.ps1',
    'LICENSE',
    'monitor.ps1',
    'package.ps1',
    'player.html',
    'PSScriptAnalyzerSettings.psd1',
    'README.md',
    'README.en.md',
    'SECURITY.md',
    'setup.cmd',
    'sources.example.json',
    'sources.json',
    'sources.schema.json',
    'start-monitor.vbs',
    'uninstall-autostart.ps1',
    'uninstall.cmd'
)
$dirs = @('.github', 'lib', 'opera-extension', 'tools')
$docs = @('banner.png', 'monitor.png', 'player.png', 'settings.png', 'tray.png', 'ideas.md', 'ROADMAP.md')

$defaultConfig = [ordered]@{
    intervalMinutes     = 5
    days                = @('Friday', 'Saturday', 'Sunday')
    playerMode          = 'embedded'
    playerBrowser       = 'auto'
    cleanPlayer         = $true
    maxPostsOnFirstRun  = 6
    notifications       = $true
    startMinimized      = $false
    openVideoOnly       = $false
    autoLoadAll         = $false
    rememberSearch      = $true
    neonTeam            = 'ferrari'
    neonCycle           = $false
    sourcesEnabled      = $true
    sourcesUrl          = 'https://raw.githubusercontent.com/necu/f1-tray-monitor/main/sources.json'
    sourcesRefreshHours = 6
    trayHint            = $true
    updateCheck         = $true
}

$forbidden = @(
    'f1_posts.json',
    'f1_state.json',
    'f1_loadall_progress.json',
    'sources.cache.json',
    'monitor.log',
    'monitor.log.old',
    'releases',
    'config.local.json'
)

function Assert-Package {
    param([string]$Pkg)

    foreach ($f in $forbidden) {
        if (Test-Path (Join-Path $Pkg $f)) { throw "El paquete no debe incluir $f" }
    }
    foreach ($f in $files) {
        if (-not (Test-Path (Join-Path $Pkg $f))) { throw "Falta $f en el paquete" }
    }
    foreach ($d in $dirs) {
        if (-not (Test-Path (Join-Path $Pkg $d))) { throw "Falta la carpeta $d en el paquete" }
    }

    $cfgPath = Join-Path $Pkg 'config.json'
    $cfg = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($k in @($defaultConfig.Keys)) {
        if ($null -eq $cfg.PSObject.Properties[$k]) { throw "config.json no incluye $k" }
    }
    if ([int]$cfg.intervalMinutes -lt 1) { throw 'config.json: intervalMinutes no valido' }

    foreach ($script in @('monitor.ps1', 'f1_scraper.ps1')) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Pkg $script))
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
            throw "$script debe conservar el BOM UTF-8"
        }
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Pkg $script), [ref]$null, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) { throw "$script no compila: $($errs[0].Message)" }
    }

    foreach ($f in @('monitor.ps1', 'player.html', 'sources.json', 'opera-extension\cleaner.js', 'opera-extension\rules.json')) {
        $a = (Get-FileHash (Join-Path $root $f) -Algorithm SHA256).Hash
        $b = (Get-FileHash (Join-Path $Pkg $f) -Algorithm SHA256).Hash
        if ($a -ne $b) { throw "El archivo $f del paquete no coincide con el proyecto" }
    }
}

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) "f1-tray-monitor-package-$Version"
if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
$pkg = Join-Path $stageRoot 'f1-tray-monitor'
New-Item -ItemType Directory -Path $pkg -Force | Out-Null

try {
    foreach ($f in $files) {
        $src = Join-Path $root $f
        if (-not (Test-Path $src)) { throw "Falta $f en el proyecto" }
        Copy-Item $src (Join-Path $pkg $f) -Force
    }
    foreach ($d in $dirs) {
        Copy-Item (Join-Path $root $d) (Join-Path $pkg $d) -Recurse -Force
    }
    $docsDir = Join-Path $pkg 'docs'
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
    foreach ($f in $docs) {
        $src = Join-Path $root "docs\$f"
        if (Test-Path $src) { Copy-Item $src (Join-Path $docsDir $f) -Force }
    }

    $defaultConfig | ConvertTo-Json -Depth 5 |
        Set-Content (Join-Path $pkg 'config.json') -Encoding UTF8

    Assert-Package $pkg

    $zipPath = if ($Verify) {
        Join-Path ([System.IO.Path]::GetTempPath()) "f1-tray-monitor-verify-$Version.zip"
    }
    else {
        $rel = Join-Path $root 'releases'
        New-Item -ItemType Directory -Path $rel -Force | Out-Null
        Join-Path $rel "F1-Tray-Monitor-$Version.zip"
    }
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    # Las entradas se crean a mano con separador '/' porque Compress-Archive y
    # ZipFile.CreateFromDirectory en .NET Framework guardan '\', lo que produce
    # nombres invalidos al descomprimir en macOS o Linux. La raiz sigue siendo
    # f1-tray-monitor/.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    $zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
    try {
        $zipWriter = New-Object System.IO.Compression.ZipArchive(
            $zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in Get-ChildItem -Path $pkg -Recurse -File) {
                $rel = $file.FullName.Substring($pkg.Length).TrimStart('\', '/') -replace '\\', '/'
                $entry = $zipWriter.CreateEntry(
                    "f1-tray-monitor/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
                # Fecha fija en las entradas: sin esto el ZIP cambia de hash en
                # cada build y SHA256SUMS deja de ser reproducible.
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $out = $entry.Open()
                try {
                    $in = [System.IO.File]::OpenRead($file.FullName)
                    try { $in.CopyTo($out) } finally { $in.Dispose() }
                }
                finally { $out.Dispose() }
            }
        }
        finally { $zipWriter.Dispose() }
    }
    finally { $zipStream.Dispose() }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($zip.Entries)
        if ($entries.Count -lt 30) { throw "El ZIP solo tiene $($entries.Count) entradas" }
        foreach ($e in $entries) {
            $name = $e.FullName -replace '\\', '/'
            if (-not $name.StartsWith('f1-tray-monitor/')) {
                throw "Entrada fuera de la raiz: $($e.FullName)"
            }
            foreach ($f in $forbidden) {
                if ($name -eq "f1-tray-monitor/$f") { throw "El ZIP incluye $f" }
            }
        }
        if (-not ($entries | Where-Object { ($_.FullName -replace '\\', '/') -eq 'f1-tray-monitor/config.json' })) {
            throw 'El ZIP no incluye config.json'
        }
    }
    finally { $zip.Dispose() }

    $bytes = (Get-Item $zipPath).Length
    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
    Write-Host ("Paquete {0}: {1} entradas, {2} bytes" -f $Version, $entries.Count, $bytes)
    Write-Host "SHA256: $hash"

    if ($Verify) {
        Write-Host 'Verificacion correcta (no se ha publicado nada).'
    }
    else {
        $sums = Join-Path $root 'releases\SHA256SUMS'
        $lines = Get-ChildItem (Join-Path $root 'releases') -Filter '*.zip' |
            Sort-Object Name |
            ForEach-Object {
                "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.Name
            }
        [System.IO.File]::WriteAllLines($sums, @($lines), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Paquete publicado en $zipPath"
        Write-Host "Hashes actualizados en $sums"
    }
}
finally {
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
    if ($Verify -and (Test-Path $zipPath)) { Remove-Item $zipPath -Force }
}
