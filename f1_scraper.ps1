<#
.SYNOPSIS
    F1 Tray Monitor - Scraper & Cache Manager
.DESCRIPTION
    Extrae entradas y opciones de reproduccion de https://descargas.eventoshq.me/category/formula-1/
    Bypasea el bloqueo DNS de las operadoras espanolas mediante DNS-over-HTTPS (Cloudflare 1.1.1.1).
    Guarda los datos en f1_posts.json ordenados de mas nuevo a mas viejo.
.PARAMETER DataDir
    Carpeta donde se guarda f1_posts.json. Por defecto, la carpeta del script.
.PARAMETER MaxPosts
    Numero de entradas a recolectar en la primera ejecucion (por defecto 6).
.PARAMETER ForceRefreshAll
    Vuelve a recolectar las ultimas MaxPosts aunque ya exista cache.
.PARAMETER CheckOnly
    Solo comprueba si hay entradas nuevas. No modifica el JSON. Exit code 0 = hay nuevas, 1 = no hay.
.PARAMETER Page
    Pagina de la categoria a leer (1 = la mas reciente). Por defecto 1.
.PARAMETER AppendPage
    Anade al cache las entradas de la pagina indicada sin tocar las existentes.
    Se usa para el boton "cargar pagina siguiente" del monitor.
#>

[CmdletBinding()]
param(
    [string]$DataDir = $PSScriptRoot,
    [int]$MaxPosts = 6,
    [switch]$ForceRefreshAll,
    [switch]$CheckOnly,
    [int]$Page = 1,
    [switch]$AppendPage,
    [int]$BatchFrom = 0,
    [int]$BatchTo = 0,
    [int]$Parallel = 8
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$baseUrl     = 'https://descargas.eventoshq.me/category/formula-1/'
if ($Page -le 1) { $categoryUrl = $baseUrl }
else { $categoryUrl = "${baseUrl}page/$Page/" }
$dohUrl      = 'https://cloudflare-dns.com/dns-query'
$userAgent   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

if (-not $DataDir) { $DataDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$jsonFile = Join-Path $DataDir 'f1_posts.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
# HTTP con DNS-over-HTTPS (curl.exe) y lectura UTF-8 real (sin mojibake)
# ---------------------------------------------------------------------------
$script:CurlExe = $null
function Get-CurlExe {
    if ($script:CurlExe -and (Test-Path $script:CurlExe)) { return $script:CurlExe }
    $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
    if (-not $curl) { $curl = "$env:SystemRoot\System32\curl.exe" }
    if (-not (Test-Path $curl)) { throw "No se encontro curl.exe" }
    $script:CurlExe = $curl
    return $curl
}

function Get-RemoteText {
    param([string]$Url, [int]$Retries = 2)

    $curl = Get-CurlExe

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $curlArgs = @(
                '-s', '-L', '--compressed',
                '--doh-url', $dohUrl,
                '--max-time', '25',
                '--retry', '1',
                '-H', "User-Agent: $userAgent",
                '-H', 'Accept-Language: es-ES,es;q=0.9,en;q=0.8',
                '-o', $tmp,
                $Url
            )
            & $curl @curlArgs | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "curl salio con codigo $LASTEXITCODE" }
            $text = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
            if ($text -and $text.Length -gt 200) { return $text }
            throw 'Respuesta vacia o demasiado corta'
        }
        catch {
            if ($attempt -ge $Retries) {
                Write-Warning "No se pudo descargar ${Url}: $_"
                return ''
            }
            Start-Sleep -Seconds 2
        }
        finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    return ''
}

# ---------------------------------------------------------------------------
# Descargas en paralelo (varias instancias de curl a la vez)
# ---------------------------------------------------------------------------
# Cargar todo hacia una peticion por pagina y otra por entrada, en serie. Con
# esta variante se lanzan hasta N descargas simultaneas y se evita el coste de
# arrancar un proceso de PowerShell para cada pagina.

function Start-CurlDownload {
    param([string]$Url)

    try { $curl = Get-CurlExe } catch { return $null }
    $tmp = [System.IO.Path]::GetTempFileName()
    $argList = @(
        '-s', '-L', '--compressed',
        '--doh-url', $dohUrl,
        '--max-time', '30',
        '--retry', '1',
        '-H', "User-Agent: $userAgent",
        '-H', 'Accept-Language: es-ES,es;q=0.9,en;q=0.8',
        '-o', $tmp,
        $Url
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curl
    $psi.Arguments = ($argList | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        return [PSCustomObject]@{ Url = $Url; Path = $tmp; Proc = $p }
    }
    catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Complete-CurlDownload {
    param($Job, [int]$Retries = 2)

    if (-not $Job) { return '' }
    $ok = $false
    try { $ok = $Job.Proc.WaitForExit(45000) } catch { }
    if (-not $ok) { try { $Job.Proc.Kill() } catch { } }

    $text = ''
    try {
        if (Test-Path $Job.Path) {
            $text = [System.IO.File]::ReadAllText($Job.Path, [System.Text.Encoding]::UTF8)
        }
    } catch { }
    Remove-Item $Job.Path -Force -ErrorAction SilentlyContinue

    if ($text -and $text.Length -gt 200) { return $text }
    # Si la descarga paralela fallo, un reintento secuencial con el metodo fiable.
    return (Get-RemoteText -Url $Job.Url -Retries $Retries)
}

function Get-RemoteTextMany {
    param([string[]]$Urls, [int]$MaxParallel = 8)

    $results = @{}
    $queue = New-Object System.Collections.Queue
    foreach ($u in @($Urls)) {
        if ($u) { $queue.Enqueue([string]$u) }
    }

    while ($queue.Count -gt 0) {
        $batch = New-Object System.Collections.ArrayList
        while ($batch.Count -lt $MaxParallel -and $queue.Count -gt 0) {
            [void]$batch.Add([string]$queue.Dequeue())
        }

        $jobs = New-Object System.Collections.ArrayList
        foreach ($u in $batch) {
            $job = Start-CurlDownload -Url $u
            if ($job) { [void]$jobs.Add($job) }
            else { $results[$u] = '' }
        }
        foreach ($job in $jobs) {
            $results[$job.Url] = Complete-CurlDownload -Job $job
        }
    }

    return $results
}

function Convert-HtmlText {
    param([string]$Text)
    if (-not $Text) { return '' }
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    $decoded = [System.Web.HttpUtility]::HtmlDecode($Text)
    return ($decoded -replace '\s+', ' ').Trim()
}

# ---------------------------------------------------------------------------
# Clasificacion de la sesion a partir del titulo
# ---------------------------------------------------------------------------
function Get-SessionType {
    param([string]$Title)

    $t = $Title.ToLowerInvariant()
    if ($t -match 'sprint\s*(shootout|qualifying|clasificaci)') { return @{ type = 'Sprint Shootout'; color = '#f59e0b' } }
    if ($t -match 'sprint')      { return @{ type = 'Sprint';      color = '#f59e0b' } }
    if ($t -match 'clasificaci') { return @{ type = 'Clasificacion'; color = '#a855f7' } }
    if ($t -match 'carrera')     { return @{ type = 'Carrera';     color = '#e10600' } }
    if ($t -match 'libres\s*3')  { return @{ type = 'Libres 3';    color = '#06b6d4' } }
    if ($t -match 'libres\s*2')  { return @{ type = 'Libres 2';    color = '#0ea5e9' } }
    if ($t -match 'libres\s*1')  { return @{ type = 'Libres 1';    color = '#38bdf8' } }
    if ($t -match 'libres')      { return @{ type = 'Libres';      color = '#38bdf8' } }
    return @{ type = 'Sesion'; color = '#3b82f6' }
}

# ---------------------------------------------------------------------------
# Extraccion de las pestanas (carrusel de opciones) de una entrada
# ---------------------------------------------------------------------------
function Get-PostOptionsFromHtml {
    param([string]$Html)

    $options = New-Object System.Collections.ArrayList
    if (-not $Html) { return @() }

    # 1) Nombres de pestana: for="#tab-XXXX" ... <H6 class="sp-tab__tab_title">NOMBRE</H6>
    $tabNames = @{}
    $tabOrder = New-Object System.Collections.ArrayList
    $navRegex = [regex]'(?is)for="#(tab-\d+)"[\s\S]{0,600}?sp-tab__tab_title[^>]*>([\s\S]*?)</H6>'
    foreach ($m in $navRegex.Matches($html)) {
        $tabId = $m.Groups[1].Value.Trim()
        $name  = Convert-HtmlText $m.Groups[2].Value
        if (-not $tabNames.ContainsKey($tabId)) {
            $tabNames[$tabId] = $name
            [void]$tabOrder.Add($tabId)
        }
    }

    # 2) Paneles: id="tab-XXXX" class="sp-tab__tab-pane ..."
    $paneRegex = [regex]'(?is)id="(tab-\d+)"\s+class="[^"]*sp-tab__tab-pane'
    $panes = $paneRegex.Matches($html)

    for ($i = 0; $i -lt $panes.Count; $i++) {
        $paneMatch = $panes[$i]
        $tabId = $paneMatch.Groups[1].Value.Trim()
        $start = $paneMatch.Index + $paneMatch.Length
        $end = if ($i + 1 -lt $panes.Count) { $panes[$i + 1].Index } else { [Math]::Min($html.Length, $start + 60000) }
        $pane = $html.Substring($start, [Math]::Max(0, $end - $start))

        $iframe = [regex]::Match($pane, '(?i)<iframe[^>]+src=["'']([^"'']+)["'']')
        if (-not $iframe.Success) { continue }

        $src = Convert-HtmlText $iframe.Groups[1].Value
        if (-not $src -or $src -notmatch '^https?://') { continue }
        if ($src -match '(?i)(doubleclick|googlesyndication|googleadservices)') { continue }

        $name = $tabNames[$tabId]
        if (-not $name) { $name = "Opcion $($options.Count + 1)" }

        [void]$options.Add([PSCustomObject]@{
            id         = $tabId
            name       = $name
            player_url = $src
            type       = 'stream'
        })
    }

    # 3) Fallback: iframes sueltos si no habia pestanas reconocibles
    if ($options.Count -eq 0) {
        $idx = 1
        $seen = @{}
        foreach ($m in [regex]::Matches($html, '(?i)<iframe[^>]+src=["'']([^"'']+)["'']')) {
            $src = Convert-HtmlText $m.Groups[1].Value
            if (-not $src -or $src -notmatch '^https?://') { continue }
            if ($src -match '(?i)(doubleclick|googlesyndication|googleadservices)') { continue }
            if ($seen.ContainsKey($src)) { continue }
            $seen[$src] = $true
            [void]$options.Add([PSCustomObject]@{
                id         = "opt-$idx"
                name       = "Reproductor $idx"
                player_url = $src
                type       = 'stream'
            })
            $idx++
        }
    }

    # Deduplicar por player_url manteniendo el primer nombre
    $unique = New-Object System.Collections.ArrayList
    $urlSeen = @{}
    foreach ($o in $options) {
        if ($urlSeen.ContainsKey($o.player_url)) { continue }
        $urlSeen[$o.player_url] = $true
        [void]$unique.Add($o)
    }

    return @($unique)
}

function Get-PostOptions {
    param([string]$PostUrl)
    $html = Get-RemoteText -Url $PostUrl
    if (-not $html) { return @() }
    return @(Get-PostOptionsFromHtml -Html $html)
}

# ---------------------------------------------------------------------------
# Parseo de la pagina de categoria
# ---------------------------------------------------------------------------
function Get-CategoryPosts {
    param([string]$Html)

    $posts = New-Object System.Collections.ArrayList
    $seen  = @{}

    # Partimos por <article ...> para no cruzar de una entrada a otra
    $blocks = [regex]::Split($Html, '(?i)(?=<article\b)')
    foreach ($block in $blocks) {
        if ($block -notmatch '(?i)<article\b') { continue }

        $idMatch = [regex]::Match($block, '(?i)<article[^>]*id="post-(\d+)"')
        if (-not $idMatch.Success) { continue }
        $postId = [int]$idMatch.Groups[1].Value
        if ($seen.ContainsKey($postId)) { continue }

        $linkMatch = [regex]::Match($block, '(?is)<a\b[^>]*?href="([^"]+)"[^>]*?aria-label="([^"]+)"')
        if (-not $linkMatch.Success) {
            $linkMatch = [regex]::Match($block, '(?is)<a\b[^>]*?aria-label="([^"]+)"[^>]*?href="([^"]+)"')
            if ($linkMatch.Success) {
                $title = Convert-HtmlText $linkMatch.Groups[1].Value
                $url   = Convert-HtmlText $linkMatch.Groups[2].Value
            } else {
                continue
            }
        } else {
            $url   = Convert-HtmlText $linkMatch.Groups[1].Value
            $title = Convert-HtmlText $linkMatch.Groups[2].Value
        }

        if (-not $url -or $url -notmatch '^https?://') { continue }

        $meta = Get-SessionType $title
        [void]$posts.Add([PSCustomObject]@{
            id          = $postId
            title       = $title
            type        = $meta.type
            badge_color = $meta.color
            url         = $url
            options     = @()
            scraped_at  = $null
        })
        $seen[$postId] = $true
    }

    return @($posts)
}

# ---------------------------------------------------------------------------
# Utilidades JSON
# ---------------------------------------------------------------------------
function Read-Cache {
    if (-not (Test-Path $jsonFile)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($jsonFile, [System.Text.Encoding]::UTF8)
        if (-not $raw -or -not $raw.Trim()) { return @() }
        $obj = $raw | ConvertFrom-Json
        return @($obj)
    }
    catch {
        Write-Warning "No se pudo leer f1_posts.json: $_"
        return @()
    }
}

function ConvertTo-JsonArray {
    param([object[]]$Items)
    $arr = @($Items)
    if ($arr.Count -eq 0) { return '[]' }
    if ($arr.Count -eq 1) {
        $one = $arr[0] | ConvertTo-Json -Depth 8
        return "[`r`n$one`r`n]"
    }
    return ($arr | ConvertTo-Json -Depth 8)
}

# Escritura atomica del cache: la ventana puede estar leyendo el JSON mientras
# el lote avanza, y no queremos que vea un archivo a medio escribir.
function Save-CacheJson {
    param([string]$Json)

    $tmp = "$jsonFile.tmp"
    [System.IO.File]::WriteAllText($tmp, $Json, $utf8NoBom)
    try {
        if (Test-Path $jsonFile) {
            try { [System.IO.File]::Replace($tmp, $jsonFile, $null) }
            catch {
                [System.IO.File]::Copy($tmp, $jsonFile, $true)
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            [System.IO.File]::Move($tmp, $jsonFile)
        }
    }
    catch {
        [System.IO.File]::WriteAllText($jsonFile, $Json, $utf8NoBom)
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Flujo principal
# ---------------------------------------------------------------------------
$existing = @(Read-Cache)
$existingById = @{}
foreach ($p in $existing) {
    if ($null -ne $p.id) { $existingById[[string]$p.id] = $p }
}

# ---------------------------------------------------------------------------
# Modo lote (boton "Cargar todo")
# ---------------------------------------------------------------------------
# Un solo proceso recorre todas las paginas y descarga las fichas en paralelo.
# Antes se lanzaba un PowerShell por pagina y se descargaba cada entrada en
# serie: decenas de arranques y cientos de peticiones encadenadas.
if ($BatchFrom -ge 2 -and $BatchTo -ge $BatchFrom) {
    $progressFile = Join-Path $DataDir 'f1_loadall_progress.json'
    $startedAt = Get-Date
    $maxParallel = [Math]::Max(1, [Math]::Min(16, $Parallel))

    function Write-LoadProgress {
        param([hashtable]$Data)
        try {
            $Data['updated'] = (Get-Date).ToString('o')
            [System.IO.File]::WriteAllText(
                $progressFile,
                ([PSCustomObject]$Data | ConvertTo-Json -Depth 4 -Compress),
                $utf8NoBom)
        } catch { }
    }

    $scanned = 0
    $lastPage = $BatchFrom - 1
    $emptyPage = 0
    $failedPage = 0
    $collected = New-Object System.Collections.ArrayList

    Write-LoadProgress @{
        active = $true; phase = 'pages'; from = $BatchFrom; to = $BatchTo
        page = $BatchFrom; pages_scanned = 0; added = 0
        total = $existing.Count; written = 0
    }

    # Fase 1: portadas de categoria, en tandas paralelas.
    $page = $BatchFrom
    while ($page -le $BatchTo) {
        $chunkEnd = [Math]::Min($BatchTo, $page + $maxParallel - 1)
        $chunkPages = New-Object System.Collections.ArrayList
        $chunkUrls = New-Object System.Collections.ArrayList
        for ($n = $page; $n -le $chunkEnd; $n++) {
            [void]$chunkPages.Add($n)
            if ($n -le 1) { [void]$chunkUrls.Add($baseUrl) }
            else { [void]$chunkUrls.Add("${baseUrl}page/$n/") }
        }

        $texts = Get-RemoteTextMany -Urls @($chunkUrls) -MaxParallel $maxParallel
        for ($i = 0; $i -lt $chunkPages.Count; $i++) {
            $n = [int]$chunkPages[$i]
            $u = [string]$chunkUrls[$i]
            $html = ''
            if ($texts.ContainsKey($u)) { $html = [string]$texts[$u] }

            if (-not $html) {
                Write-Warning "No se pudo leer la pagina $n"
                $failedPage = $n
                break
            }

            $pagePosts = @(Get-CategoryPosts -Html $html)
            $scanned++
            if ($pagePosts.Count -eq 0) {
                $emptyPage = $n
                break
            }

            $lastPage = $n
            foreach ($p in $pagePosts) {
                $key = [string]$p.id
                if ($existingById.ContainsKey($key)) { continue }
                $existingById[$key] = $p
                [void]$collected.Add($p)
            }

            Write-LoadProgress @{
                active = $true; phase = 'pages'; from = $BatchFrom; to = $BatchTo
                page = $n; pages_scanned = $scanned; added = $collected.Count
                total = $existing.Count; written = 0
            }
            Write-Host "Pagina ${n}: $($pagePosts.Count) entradas, $($collected.Count) nuevas acumuladas"
        }

        if ($emptyPage -or $failedPage) { break }
        $page = $chunkEnd + 1
    }

    # Fase 2: fichas de cada entrada nueva, tambien en tandas paralelas.
    $processed = New-Object System.Collections.ArrayList
    $totalNew = $collected.Count
    $done = 0
    $written = 0
    $lastWrite = Get-Date

    if ($totalNew -gt 0) {
        Write-LoadProgress @{
            active = $true; phase = 'details'; from = $BatchFrom; to = $BatchTo
            page = $lastPage; pages_scanned = $scanned; added = 0
            total = $existing.Count; done = 0; new_total = $totalNew; written = 0
        }

        for ($offset = 0; $offset -lt $totalNew; $offset += $maxParallel) {
            $end = [Math]::Min($offset + $maxParallel - 1, $totalNew - 1)
            $chunk = New-Object System.Collections.ArrayList
            for ($k = $offset; $k -le $end; $k++) { [void]$chunk.Add($collected[$k]) }

            $urls = @($chunk | ForEach-Object { [string]$_.url })
            $texts = Get-RemoteTextMany -Urls $urls -MaxParallel $maxParallel

            foreach ($p in $chunk) {
                $u = [string]$p.url
                $html = ''
                if ($texts.ContainsKey($u)) { $html = [string]$texts[$u] }
                if ($html) { $p.options = @(Get-PostOptionsFromHtml -Html $html) }
                else { $p.options = @() }
                $p.scraped_at = (Get-Date).ToString('o')
                [void]$processed.Add($p)
                $done++
            }

            # Volcar el cache cada ~2 s para que la ventana vea crecer la lista.
            $now = Get-Date
            if ($done -ge $totalNew -or (($now - $lastWrite).TotalSeconds -ge 2)) {
                $partial = @(@($existing) + @($processed) | Sort-Object -Property id -Descending)
                Save-CacheJson -Json (ConvertTo-JsonArray -Items $partial)
                $written++
                $lastWrite = $now
            }

            Write-LoadProgress @{
                active = $true; phase = 'details'; from = $BatchFrom; to = $BatchTo
                page = $lastPage; pages_scanned = $scanned; added = $processed.Count
                total = ($existing.Count + $processed.Count)
                done = $done; new_total = $totalNew; written = $written
            }
            Write-Host "Fichas: $done/$totalNew"
        }
    }

    $final = @(@($existing) + @($processed) | Sort-Object -Property id -Descending)
    if ($processed.Count -gt 0) {
        Save-CacheJson -Json (ConvertTo-JsonArray -Items $final)
    }

    $elapsed = [int]((Get-Date) - $startedAt).TotalMilliseconds
    $result = [PSCustomObject]@{
        batch         = $true
        from          = $BatchFrom
        to            = $BatchTo
        last_page     = [Math]::Max(1, $lastPage)
        empty_page    = $emptyPage
        failed_page   = $failedPage
        pages_scanned = $scanned
        added         = $processed.Count
        total_posts   = $final.Count
        elapsed_ms    = $elapsed
    }

    Write-LoadProgress @{
        active = $false; phase = 'done'; from = $BatchFrom; to = $BatchTo
        last_page = $result.last_page; empty_page = $emptyPage; failed_page = $failedPage
        pages_scanned = $scanned; added = $processed.Count
        total = $final.Count; written = $written; elapsed_ms = $elapsed
    }

    Write-Host ($result | ConvertTo-Json -Compress)
    exit 0
}

Write-Host 'Escaneando categoria F1 (DNS-over-HTTPS Cloudflare)...'
$catHtml = Get-RemoteText -Url $categoryUrl
if (-not $catHtml) {
    Write-Error "No se pudo conectar a $categoryUrl"
    if ($CheckOnly) { exit 1 }
    return
}

$pagePosts = @(Get-CategoryPosts -Html $catHtml)
Write-Host "Entradas encontradas en la pagina $($Page): $($pagePosts.Count)"

# --- Modo "cargar pagina siguiente": anadir sin notificar -------------------
if ($AppendPage -and -not $CheckOnly) {
    $added = New-Object System.Collections.ArrayList
    foreach ($p in $pagePosts) {
        if ($existingById.ContainsKey([string]$p.id)) { continue }
        Write-Host " -> Pagina $Page : [$($p.type)] $($p.title)"
        $opts = @(Get-PostOptions -PostUrl $p.url)
        $p.options = $opts
        $p.scraped_at = (Get-Date).ToString('o')
        [void]$added.Add($p)
        $existingById[[string]$p.id] = $p
    }

    $final = @(@($existing) + @($added) | Sort-Object -Property id -Descending)
    $json = ConvertTo-JsonArray -Items $final
    Save-CacheJson -Json $json

    $out = [PSCustomObject]@{
        page        = $Page
        page_posts  = $pagePosts.Count
        added       = $added.Count
        total_posts = $final.Count
        json_path   = $jsonFile
    }
    Write-Host ($out | ConvertTo-Json -Depth 4 -Compress)
    exit 0
}

$newIds = @()
foreach ($p in $pagePosts) {
    if (-not $existingById.ContainsKey([string]$p.id)) { $newIds += $p.id }
}

if ($CheckOnly) {
    $out = [PSCustomObject]@{
        checked_at  = (Get-Date).ToString('o')
        page_posts  = $pagePosts.Count
        new_ids     = @($newIds)
        new_count   = $newIds.Count
        cache_count = $existing.Count
    }
    Write-Host ($out | ConvertTo-Json -Depth 4 -Compress)
    if ($newIds.Count -gt 0) { exit 0 } else { exit 1 }
}

$result = [PSCustomObject]@{
    total_posts = 0
    new_posts   = @()
    json_path   = $jsonFile
}

if ($existing.Count -eq 0 -or $ForceRefreshAll) {
    # Primera ejecucion: recolectar las ultimas MaxPosts de la primera pagina
    Write-Host "Primera ejecucion: recolectando las ultimas $MaxPosts entradas..."
    $batch = @($pagePosts | Select-Object -First $MaxPosts)
    $collected = New-Object System.Collections.ArrayList

    foreach ($p in $batch) {
        Write-Host " -> Extrayendo opciones: [$($p.type)] $($p.title)"
        $opts = @(Get-PostOptions -PostUrl $p.url)
        $p.options = $opts
        $p.scraped_at = (Get-Date).ToString('o')
        [void]$collected.Add($p)
    }

    $final = @($collected | Sort-Object -Property id -Descending)
}
else {
    # Ejecucion incremental: solo descargar opciones de entradas nuevas
    $newPosts = New-Object System.Collections.ArrayList
    foreach ($p in $pagePosts) {
        if ($existingById.ContainsKey([string]$p.id)) { continue }
        Write-Host " ¡NUEVA ENTRADA! [$($p.type)] $($p.title)"
        $opts = @(Get-PostOptions -PostUrl $p.url)
        $p.options = $opts
        $p.scraped_at = (Get-Date).ToString('o')
        [void]$newPosts.Add($p)
    }

    # Actualizar metadatos de las existentes (sin re-scrapear sus opciones)
    $merged = New-Object System.Collections.ArrayList
    foreach ($p in $pagePosts) {
        if ($existingById.ContainsKey([string]$p.id)) {
            $old = $existingById[[string]$p.id]
            $old.title = $p.title
            $old.type = $p.type
            $old.badge_color = $p.badge_color
            $old.url = $p.url
            if (-not $old.options) { $old | Add-Member -NotePropertyName options -NotePropertyValue @() -Force }
            if (-not $old.scraped_at) { $old | Add-Member -NotePropertyName scraped_at -NotePropertyValue (Get-Date).ToString('o') -Force }
            [void]$merged.Add($old)
            $existingById.Remove([string]$p.id)
        }
    }
    foreach ($p in $newPosts) { [void]$merged.Add($p) }
    # Conservar entradas antiguas que ya no estan en la primera pagina
    foreach ($key in $existingById.Keys) { [void]$merged.Add($existingById[$key]) }

    $final = @($merged | Sort-Object -Property id -Descending)
    $result.new_posts = @($newPosts)
}

$json = ConvertTo-JsonArray -Items $final
Save-CacheJson -Json $json

$result.total_posts = $final.Count
Write-Host "Guardado en $jsonFile con $($final.Count) entradas."
return $result
