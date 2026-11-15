# Alta guiada de una fuente en el catalogo (sources.json).
#
#   .\tools\add-source.ps1 -Url "https://ejemplo.com/embed/abc" -Name "DAZN ES" `
#       -Service dazn -Quality 1080p -Lang ES -Year 2026 -Gp brasil -Session Carrera
#
#   .\tools\add-source.ps1 -RuleJson '{"enabled":true,"options":[...]}' -DryRun
#
# Valida la URL, comprueba el servicio contra sources.json, evita duplicados, guarda
# una copia de seguridad y ejecuta check_sources.ps1 antes de dar el cambio por bueno.
[CmdletBinding()]
param(
    [string]$Url = '',
    [string]$Name = '',
    [string]$Service = '',
    [string]$Quality = '',
    [string]$Lang = '',
    [int]$Priority = 10,
    [string]$Starts = '',
    [string]$Expires = '',
    [string]$Gp = '',
    [int]$Year = 0,
    [string]$Session = '',
    [string]$TitleContains = '',
    [string]$Type = '',
    [string]$Id = '',
    [switch]$Primary,
    [switch]$Any,
    [string]$RuleJson = '',
    [string]$Path = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = Join-Path $root 'sources.json' }
$Path = [System.IO.Path]::GetFullPath($Path)

function Fail {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Parse-Date {
    param([string]$Value, [string]$Field)
    if (-not $Value) { return $null }
    $dt = [datetime]::MinValue
    if (-not [datetime]::TryParse($Value, [ref]$dt)) { Fail "$Field no es una fecha valida (usa 2026-11-15 o ISO 8601)." }
    return $Value
}

if (-not (Test-Path $Path)) { Fail "no existe el catalogo: $Path" }

try {
    $catalog = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}
catch { Fail "el catalogo no es JSON valido: $($_.Exception.Message)" }

if (-not $catalog.rules) {
    $catalog | Add-Member -NotePropertyName rules -NotePropertyValue @() -Force
}
$rules = @($catalog.rules)

$newRule = $null
if ($RuleJson) {
    try { $newRule = $RuleJson | ConvertFrom-Json }
    catch { Fail "RuleJson no es JSON valido: $($_.Exception.Message)" }
    foreach ($field in @('options')) {
        if (-not $newRule.$field) { Fail "RuleJson debe incluir '$field'." }
    }
}
else {
    if (-not $Url) { Fail 'indicа -Url o -RuleJson.' }
    if ($Url -notmatch '^https?://') { Fail "la URL debe empezar por http:// o https:// ($Url)" }

    $match = [ordered]@{}
    if ($Any) { $match.any = $true }
    if ($Id) { $match.id = $Id }
    if ($Year -gt 0) { $match.year = $Year }
    if ($Gp) { $match.gp = $Gp }
    if ($Session) { $match.session = $Session }
    if ($TitleContains) { $match.titleContains = $TitleContains }
    if ($Type) { $match.type = $Type }
    if ($match.Count -eq 0) {
        Fail 'indica al menos una condicion (-Any, -Gp, -Session, -Year, -Id, -TitleContains o -Type).'
    }

    if ($Service) {
        if (-not $catalog.services.PSObject.Properties[[string]$Service]) {
            $known = @($catalog.services.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
            Fail "servicio desconocido '$Service'. Disponibles: $known"
        }
    }

    $optionName = if ($Name) { $Name } else { ([uri]$Url).Host }
    $option = [ordered]@{ name = $optionName; url = $Url }
    if ($Service) { $option.service = $Service }
    if ($Quality) { $option.quality = $Quality }
    if ($Lang) { $option.lang = $Lang }
    if ($Primary) { $option.primary = $true }

    $newRule = [ordered]@{
        enabled  = $true
        priority = $Priority
    }
    $startsValue = Parse-Date $Starts 'starts'
    $expiresValue = Parse-Date $Expires 'expires'
    if ($startsValue) { $newRule.starts = $startsValue }
    if ($expiresValue) { $newRule.expires = $expiresValue }
    $newRule.match = $match
    $newRule.options = @($option)
}

# Duplicados: misma URL ya publicada en cualquier regla.
$newUrls = @($newRule.options | ForEach-Object { [string]$_.url })
foreach ($rule in $rules) {
    foreach ($opt in @($rule.options)) {
        if ($newUrls -contains [string]$opt.url) {
            Fail "la URL ya existe en el catalogo: $($opt.url)"
        }
    }
}

$catalog.version = [int]$catalog.version + 1
$catalog.updated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$catalog.rules = @($rules + $newRule)

$json = $catalog | ConvertTo-Json -Depth 20
if ($DryRun) {
    Write-Host '--- Regla que se anadiria ---' -ForegroundColor Cyan
    $newRule | ConvertTo-Json -Depth 10
    Write-Host "--- Catalogo resultante: $($catalog.rules.Count) reglas, version $($catalog.version) ---" -ForegroundColor Cyan
    exit 0
}

$backup = "$Path.bak"
Copy-Item $Path $backup -Force
$tmp = "$Path.tmp"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tmp, $json, $utf8)

try {
    & (Join-Path $root 'check_sources.ps1') -Files $tmp | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'check_sources.ps1 ha rechazado el catalogo' }
    Move-Item $tmp $Path -Force
    Write-Host "Fuente anadida. Reglas: $($catalog.rules.Count). Version: $($catalog.version)." -ForegroundColor Green
    Write-Host "Copia de seguridad: $backup"
}
catch {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Copy-Item $backup $Path -Force
    Fail "no se ha modificado el catalogo: $($_.Exception.Message)"
}
