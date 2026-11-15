# Valida de forma estructural sources.json y sources.example.json sin
# dependencias externas. Se usa en local y en la integracion continua.
# Uso: powershell -ExecutionPolicy Bypass -File check_sources.ps1
param(
    [string[]]$Files = @('sources.json', 'sources.example.json')
)

$script:failed = $false

function Fail {
    param([string]$File, [string]$Message)
    Write-Host "::error file=$File::$Message"
    $script:failed = $true
}

foreach ($f in $Files) {
    if (-not (Test-Path $f)) {
        Fail $f 'el archivo no existe'
        continue
    }

    try {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path $f), [System.Text.Encoding]::UTF8)
        $cat = $raw | ConvertFrom-Json
    }
    catch {
        Fail $f "JSON no valido: $($_.Exception.Message)"
        continue
    }

    if ($null -eq $cat.version -or -not ([int]$cat.version -ge 1)) {
        Fail $f 'version debe ser un entero mayor o igual que 1'
    }
    if ($null -ne $cat.refreshHours) {
        $n = 0
        if (-not [int]::TryParse([string]$cat.refreshHours, [ref]$n) -or $n -lt 1 -or $n -gt 168) {
            Fail $f 'refreshHours debe estar entre 1 y 168'
        }
    }

    $services = @()
    if ($cat.services) { $services = @($cat.services.PSObject.Properties) }
    if ($services.Count -eq 0) {
        Fail $f 'services debe contener al menos un servicio'
    }
    foreach ($svc in $services) {
        $v = $svc.Value
        if (-not $v.label) { Fail $f "servicio '$($svc.Name)' sin label" }
        if (-not $v.short) { Fail $f "servicio '$($svc.Name)' sin short" }
        if (([string]$v.color) -notmatch '^#[0-9A-Fa-f]{6}$') {
            Fail $f "servicio '$($svc.Name)' con color no valido (usa #RRGGBB)"
        }
    }

    $idx = 0
    if ($null -eq $cat.rules) {
        Fail $f 'rules debe ser un array (puede estar vacio)'
        continue
    }
    foreach ($rule in @($cat.rules)) {
        $idx++
        $tag = "regla #$idx"
        if ($null -eq $rule) { Fail $f "$tag vacia"; continue }

        if ($null -ne $rule.priority) {
            $p = 0
            if (-not [int]::TryParse([string]$rule.priority, [ref]$p)) {
                Fail $f "${tag}: priority debe ser numerico"
            }
        }
        foreach ($field in @('starts', 'expires')) {
            $value = $rule.$field
            if ($value) {
                $dt = [datetime]::MinValue
                if (-not [datetime]::TryParse([string]$value, [ref]$dt)) {
                    Fail $f "${tag}: $field no es una fecha valida"
                }
            }
        }

        $opts = @($rule.options)
        if ($opts.Count -eq 0) {
            Fail $f "$tag sin ninguna opcion"
            continue
        }
        foreach ($o in $opts) {
            if ($null -eq $o) { Fail $f "$tag con una opcion vacia"; continue }
            if (-not $o.name) { Fail $f "${tag}: opcion sin name" }
            if (([string]$o.url) -notmatch '^https?://') {
                Fail $f "${tag}: URL no valida '$($o.url)'"
            }
            if ($o.service -and -not ($cat.services.PSObject.Properties[[string]$o.service])) {
                Fail $f "${tag}: servicio desconocido '$($o.service)'"
            }
        }
    }

    Write-Host ("Catalogo OK: {0} (v{1}, {2} servicios, {3} reglas)" -f $f, $cat.version, $services.Count, @($cat.rules).Count)
}

if ($script:failed) { exit 1 }
exit 0
