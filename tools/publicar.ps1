# Publica F1 Tray Monitor en GitHub en un solo paso.
#
#   .\tools\publicar.ps1 -DryRun     -> muestra el plan sin tocar nada
#   .\tools\publicar.ps1             -> commit, repo, topics, Pages y tag v<version>
#
# Requisitos: Git, GitHub CLI y una sesion iniciada (`gh auth login`).
# El script no guarda credenciales: usa las que ya tenga gh en el Credential Manager.
[CmdletBinding()]
param(
    [string]$Owner = 'necu',
    [string]$Repo = 'f1-tray-monitor',
    [string]$Version = '',
    [switch]$DryRun,
    [switch]$SkipPages,
    [switch]$SkipRelease
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $Version) {
    $line = Select-String -Path (Join-Path $root 'monitor.ps1') -Pattern "AppVersion\s*=\s*'([^']+)'" |
        Select-Object -First 1
    if (-not $line) { throw 'No se pudo leer AppVersion de monitor.ps1' }
    $Version = [regex]::Match($line.Line, "'([^']+)'").Groups[1].Value
}

$tag = "v$Version"
$description = 'Monitor de escritorio para Windows que avisa de las nuevas sesiones de F1 y las reproduce dentro de la app. Portable, sin instalador y sin telemetria.'
$homepage = "https://$($Owner.ToLower()).github.io/$Repo/"
$commitMessage = "$Version`: monitor de F1 en la bandeja con catalogo remoto, favoritos y reproductor embebido"
$topics = @('formula1', 'f1', 'powershell', 'winforms', 'webview2', 'windows', 'desktop-app', 'tray', 'motorsport', 'open-source')

function Show-Plan {
    Write-Host ''
    Write-Host "  git init -b main" -ForegroundColor DarkGray
    Write-Host "  git config user.name <tu-usuario>" -ForegroundColor DarkGray
    Write-Host "  git config user.email <tu-usuario>@users.noreply.github.com" -ForegroundColor DarkGray
    Write-Host "  git add -A && git commit -m `"$commitMessage`"" -ForegroundColor DarkGray
    Write-Host "  gh repo create $Owner/$Repo --public --source . --remote origin --push" -ForegroundColor DarkGray
    Write-Host "  gh repo edit $Owner/$Repo --description `"$description`" --homepage `"$homepage`"" -ForegroundColor DarkGray
    foreach ($t in $topics) { Write-Host "    --add-topic $t" -ForegroundColor DarkGray }
    if (-not $SkipPages) {
        Write-Host "  gh api --method POST repos/$Owner/$Repo/pages -f source[branch]=main -f source[path]=/docs" -ForegroundColor DarkGray
    }
    if (-not $SkipRelease) {
        Write-Host "  git tag -a $tag -m `"$Version - F1 Tray Monitor`"" -ForegroundColor DarkGray
        Write-Host "  git push origin $tag   # release.yml empaqueta y adjunta el ZIP" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-Step {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$What
    )

    Write-Host "  -> $What" -ForegroundColor Cyan
    # Git y gh escriben avisos por stderr. En PowerShell 5.1, con
    # ErrorActionPreference='Stop' y 2>&1, un aviso se convierte en excepcion:
    # aqui solo manda el codigo de salida.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) {
        $out | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkYellow }
        throw "$What fallo (exit $code)"
    }
    return @($out)
}

function Invoke-Probe {
    param([string]$Exe, [string[]]$Arguments)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return @{ Code = $code; Output = @($out) }
}

# --- Comprobaciones previas ------------------------------------------------
$gitExe = 'git'
$ghExe = 'gh'
if (-not (Get-Command $gitExe -ErrorAction SilentlyContinue)) {
    if (Test-Path 'C:\Program Files\Git\cmd\git.exe') { $gitExe = 'C:\Program Files\Git\cmd\git.exe' }
    else { throw 'Git no esta instalado. Ejecuta: winget install --id Git.Git -e' }
}
if (-not (Get-Command $ghExe -ErrorAction SilentlyContinue)) {
    if (Test-Path 'C:\Program Files\GitHub CLI\gh.exe') { $ghExe = 'C:\Program Files\GitHub CLI\gh.exe' }
    else { throw 'GitHub CLI no esta instalado. Ejecuta: winget install --id GitHub.cli -e' }
}

if ($DryRun) {
    Write-Host ''
    Write-Host "Plan de publicacion de F1 Tray Monitor $Version" -ForegroundColor White
    Write-Host "  repo: $Owner/$Repo"
    Write-Host "  tag:  $tag"
    Show-Plan
    Write-Host '  No se ha ejecutado nada (-DryRun).' -ForegroundColor Yellow
    exit 0
}

$auth = Invoke-Probe $ghExe @('auth', 'status')
if ($auth.Code -ne 0) {
    Write-Host ''
    Write-Host 'GitHub CLI no tiene sesion iniciada.' -ForegroundColor Yellow
    Write-Host 'Ejecuta esto en tu terminal y vuelve a lanzar el script:' -ForegroundColor Yellow
    Write-Host '  gh auth login' -ForegroundColor White
    Write-Host ''
    Write-Host 'Elige: GitHub.com -> HTTPS -> Login with a web browser.' -ForegroundColor Gray
    Write-Host 'El token queda en el Credential Manager; este script no lo ve.' -ForegroundColor Gray
    exit 1
}

$login = (& $ghExe api user --jq .login 2>$null)
if (-not $login) { throw 'No se pudo leer el usuario autenticado de gh.' }
Write-Host "Sesion de GitHub: $login" -ForegroundColor Green

# Si el dueno no es el usuario autenticado, avisa pero respeta el parametro.
if ($Owner -ne $login) {
    Write-Host "  Aviso: publicaras en '$Owner' con la sesion de '$login'." -ForegroundColor Yellow
}

# --- Identidad local del repositorio ---------------------------------------
$name = (& $gitExe config user.name 2>$null)
if (-not $name) { Invoke-Step $gitExe @('config', 'user.name', $login) 'configurar user.name' | Out-Null }
$email = (& $gitExe config user.email 2>$null)
if (-not $email) {
    Invoke-Step $gitExe @('config', 'user.email', "$login@users.noreply.github.com") 'configurar user.email' | Out-Null
}

# --- Commit inicial ---------------------------------------------------------
if (-not (Test-Path (Join-Path $root '.git'))) {
    Invoke-Step $gitExe @('init', '-b', 'main') 'inicializar el repositorio' | Out-Null
}

Invoke-Step $gitExe @('add', '-A') 'preparar archivos' | Out-Null

$forbidden = & $gitExe ls-files | Select-String -Pattern '(^|/)(f1_posts\.json|f1_state\.json|f1_loadall_progress\.json|sources\.cache\.json|monitor\.log|monitor\.log\.old)$'
if ($forbidden) {
    throw "Hay archivos de ejecucion preparados para el commit: $($forbidden -join ', ')"
}

$pending = & $gitExe status --porcelain
if ($pending) {
    Invoke-Step $gitExe @('commit', '-m', $commitMessage) 'crear el commit' | Out-Null
}
else {
    Write-Host '  Sin cambios pendientes: se reutiliza el ultimo commit.' -ForegroundColor Gray
}

# --- Repositorio remoto -----------------------------------------------------
$view = Invoke-Probe $ghExe @('repo', 'view', "$Owner/$Repo", '--json', 'name')
if ($view.Code -ne 0) {
    Invoke-Step $ghExe @(
        'repo', 'create', "$Owner/$Repo", '--public', '--source', '.',
        '--remote', 'origin', '--push', '--description', $description
    ) 'crear el repositorio y subir main' | Out-Null
}
else {
    $remotes = @(& $gitExe remote)
    if ($remotes -notcontains 'origin') {
        Invoke-Step $gitExe @('remote', 'add', 'origin', "https://github.com/$Owner/$Repo.git") 'anadir origin' | Out-Null
    }
    Invoke-Step $gitExe @('push', '-u', 'origin', 'main') 'subir main' | Out-Null
}

# --- Ficha del repositorio --------------------------------------------------
$editArgs = @(
    'repo', 'edit', "$Owner/$Repo",
    '--description', $description,
    '--homepage', $homepage
)
foreach ($t in $topics) { $editArgs += @('--add-topic', $t) }
Invoke-Step $ghExe $editArgs 'actualizar descripcion, web y topics' | Out-Null

# --- GitHub Pages -----------------------------------------------------------
if (-not $SkipPages) {
    $pages = Invoke-Probe $ghExe @('api', "repos/$Owner/$Repo/pages")
    if ($pages.Code -ne 0) {
        Invoke-Step $ghExe @(
            'api', '--method', 'POST', "repos/$Owner/$Repo/pages",
            '-f', 'source[branch]=main', '-f', 'source[path]=/docs'
        ) 'activar GitHub Pages' | Out-Null
    }
    else {
        Invoke-Step $ghExe @(
            'api', '--method', 'PUT', "repos/$Owner/$Repo/pages",
            '-f', 'source[branch]=main', '-f', 'source[path]=/docs'
        ) 'actualizar GitHub Pages' | Out-Null
    }
}

# --- Tag y release ----------------------------------------------------------
if (-not $SkipRelease) {
    $localTag = & $gitExe tag -l $tag
    if (-not $localTag) {
        Invoke-Step $gitExe @('tag', '-a', $tag, '-m', "$Version - F1 Tray Monitor") "crear el tag $tag" | Out-Null
    }
    $remoteTag = & $gitExe ls-remote --tags origin "refs/tags/$tag" 2>$null
    if (-not $remoteTag) {
        Invoke-Step $gitExe @('push', 'origin', $tag) "subir el tag $tag" | Out-Null
    }
    else {
        Write-Host "  El tag $tag ya estaba en el remoto." -ForegroundColor Gray
    }
}

# --- Resumen ----------------------------------------------------------------
Write-Host ''
Write-Host 'Publicado.' -ForegroundColor Green
Write-Host "  Repo:    https://github.com/$Owner/$Repo"
Write-Host "  Pages:   $homepage"
Write-Host "  Release: https://github.com/$Owner/$Repo/releases/tag/$tag"
Write-Host "  Actions: https://github.com/$Owner/$Repo/actions"
Write-Host ''
Write-Host 'Quedan dos pasos manuales (2 minutos):' -ForegroundColor Yellow
Write-Host '  1. Settings > Social preview > subir docs/social-preview.png'
Write-Host '  2. Settings > Pages: comprobar que publica main /docs'
Write-Host ''
Write-Host 'El workflow release.yml adjunta el ZIP y SHA256SUMS al tag.' -ForegroundColor Gray
