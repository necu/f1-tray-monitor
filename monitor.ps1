# ===========================================================================
#  F1 Tray Monitor
#  - Icono en la bandeja con menu contextual (click derecho)
#  - Ventana con buscador, tarjetas en acordeon y botones de reproduccion
#  - Notificaciones de Windows cuando aparece una entrada nueva
#  - Paginacion del blog ("cargar pagina siguiente")
#  - Reproductor limpio en Opera con perfil aislado y extension propia
#  - Scrapea cada N minutos usando f1_scraper.ps1 (DNS-over-HTTPS)
#
#  Licencia MIT. Ver LICENSE en la raiz del proyecto.
# ===========================================================================

param(
    [string]$DataDir = $PSScriptRoot,
    [int]$IntervalMinutes = 0,
    [switch]$ScrapeAllDays,
    [switch]$SelfTest,
    [string]$SelfTestAction = ''
)

$ErrorActionPreference = 'Stop'

if (-not $DataDir) { $DataDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$scriptDir   = $DataDir
$dataFile    = Join-Path $scriptDir 'f1_posts.json'
$stateFile   = Join-Path $scriptDir 'f1_state.json'
$configFile  = Join-Path $scriptDir 'config.json'
$scraperFile = Join-Path $scriptDir 'f1_scraper.ps1'
$playerHtml  = Join-Path $scriptDir 'player.html'
$extensionDir = Join-Path $scriptDir 'opera-extension'
$logFile     = Join-Path $scriptDir 'monitor.log'
$psExe       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# Catálogo de fuentes: archivo estático editable (por ejemplo en GitHub).
# La app usa primero la copia local, luego la descarga remota y, si algo falla,
# mantiene la última copia buena en sources.cache.json.
$sourcesFile      = Join-Path $scriptDir 'sources.json'
$sourcesCacheFile = Join-Path $scriptDir 'sources.cache.json'
$sourcesTmpFile   = Join-Path $scriptDir 'sources.cache.tmp'
$sourcesDefaultUrl = 'https://raw.githubusercontent.com/necu/f1-tray-monitor/main/sources.json'
$script:SourcesDefaultUrl = $sourcesDefaultUrl
$script:AppVersion = '1.3.0'
$script:AppRepo = 'necu/f1-tray-monitor'

# --- Configuracion --------------------------------------------------------
$script:Config = @{
    intervalMinutes    = 5
    days               = @('Friday', 'Saturday', 'Sunday')
    playerMode         = 'embedded'
    playerBrowser      = 'auto'
    cleanPlayer        = $true
    maxPostsOnFirstRun = 6
    notifications      = $true
    startMinimized     = $false
    openVideoOnly      = $false
    autoLoadAll        = $false
    rememberSearch     = $true
    neonTeam           = 'ferrari'
    neonCycle          = $false
    sourcesEnabled     = $true
    sourcesUrl         = $sourcesDefaultUrl
    sourcesRefreshHours = 6
    trayHint           = $true
    updateCheck        = $true
}
if (Test-Path $configFile) {
    try {
        $cfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $cfg.intervalMinutes) { $script:Config.intervalMinutes = [int]$cfg.intervalMinutes }
        if ($null -ne $cfg.days) { $script:Config.days = @($cfg.days | ForEach-Object { [string]$_ }) }
        if ($cfg.playerMode) { $script:Config.playerMode = ([string]$cfg.playerMode).ToLowerInvariant() }
        if ($cfg.playerBrowser) { $script:Config.playerBrowser = [string]$cfg.playerBrowser }
        if ($null -ne $cfg.cleanPlayer) { $script:Config.cleanPlayer = [bool]$cfg.cleanPlayer }
        if ($null -ne $cfg.maxPostsOnFirstRun) { $script:Config.maxPostsOnFirstRun = [int]$cfg.maxPostsOnFirstRun }
        if ($null -ne $cfg.notifications) { $script:Config.notifications = [bool]$cfg.notifications }
        if ($null -ne $cfg.startMinimized) { $script:Config.startMinimized = [bool]$cfg.startMinimized }
        if ($null -ne $cfg.openVideoOnly) { $script:Config.openVideoOnly = [bool]$cfg.openVideoOnly }
        if ($null -ne $cfg.autoLoadAll) { $script:Config.autoLoadAll = [bool]$cfg.autoLoadAll }
        if ($null -ne $cfg.rememberSearch) { $script:Config.rememberSearch = [bool]$cfg.rememberSearch }
        if ($cfg.neonTeam) { $script:Config.neonTeam = ([string]$cfg.neonTeam).ToLowerInvariant() }
        if ($null -ne $cfg.neonCycle) { $script:Config.neonCycle = [bool]$cfg.neonCycle }
        if ($null -ne $cfg.sourcesEnabled) { $script:Config.sourcesEnabled = [bool]$cfg.sourcesEnabled }
        if ($cfg.sourcesUrl) { $script:Config.sourcesUrl = [string]$cfg.sourcesUrl }
        if ($null -ne $cfg.sourcesRefreshHours) { $script:Config.sourcesRefreshHours = [int]$cfg.sourcesRefreshHours }
        if ($null -ne $cfg.trayHint) { $script:Config.trayHint = [bool]$cfg.trayHint }
        if ($null -ne $cfg.updateCheck) { $script:Config.updateCheck = [bool]$cfg.updateCheck }
    } catch { }
}
if (-not $script:Config.sourcesUrl) { $script:Config.sourcesUrl = $sourcesDefaultUrl }
$script:Config.sourcesRefreshHours = [Math]::Max(1, [Math]::Min(168, [int]$script:Config.sourcesRefreshHours))
if ($script:Config.playerMode -notin @('embedded', 'external')) { $script:Config.playerMode = 'embedded' }
if ($IntervalMinutes -le 0) { $IntervalMinutes = [Math]::Max(1, [int]$script:Config.intervalMinutes) }
$script:ScrapeDays = @($script:Config.days)
if ($script:ScrapeDays.Count -eq 0) { $script:ScrapeDays = @('Friday', 'Saturday', 'Sunday') }

# Catalogo de equipos para el neon del reproductor (claves compartidas con player.html).
$script:NeonTeams = @(
    [PSCustomObject]@{ key = 'ferrari';  name = 'Ferrari' },
    [PSCustomObject]@{ key = 'mclaren';  name = 'McLaren' },
    [PSCustomObject]@{ key = 'mercedes'; name = 'Mercedes' },
    [PSCustomObject]@{ key = 'redbull';  name = 'Red Bull' },
    [PSCustomObject]@{ key = 'williams'; name = 'Williams' },
    [PSCustomObject]@{ key = 'alpine';   name = 'Alpine' },
    [PSCustomObject]@{ key = 'aston';    name = 'Aston Martin' },
    [PSCustomObject]@{ key = 'haas';     name = 'Haas' },
    [PSCustomObject]@{ key = 'sauber';   name = 'Sauber' },
    [PSCustomObject]@{ key = 'lotus';    name = 'Lotus' },
    [PSCustomObject]@{ key = 'brawn';    name = 'Brawn GP' },
    [PSCustomObject]@{ key = 'renault';  name = 'Renault' }
)
if (-not ($script:NeonTeams | Where-Object { $_.key -eq $script:Config.neonTeam })) {
    $script:Config.neonTeam = 'ferrari'
}

function Get-ConfigSnapshot {
    # Unica fuente de verdad para guardar y exportar config.json.
    return [ordered]@{
        intervalMinutes    = [int]$script:Config.intervalMinutes
        days               = @($script:Config.days)
        playerMode         = [string]$script:Config.playerMode
        playerBrowser      = [string]$script:Config.playerBrowser
        cleanPlayer        = [bool]$script:Config.cleanPlayer
        maxPostsOnFirstRun = [int]$script:Config.maxPostsOnFirstRun
        notifications      = [bool]$script:Config.notifications
        startMinimized     = [bool]$script:Config.startMinimized
        openVideoOnly      = [bool]$script:Config.openVideoOnly
        autoLoadAll        = [bool]$script:Config.autoLoadAll
        rememberSearch     = [bool]$script:Config.rememberSearch
        neonTeam           = [string]$script:Config.neonTeam
        neonCycle          = [bool]$script:Config.neonCycle
        sourcesEnabled     = [bool]$script:Config.sourcesEnabled
        sourcesUrl         = [string]$script:Config.sourcesUrl
        sourcesRefreshHours = [int]$script:Config.sourcesRefreshHours
        trayHint           = [bool]$script:Config.trayHint
        updateCheck        = [bool]$script:Config.updateCheck
    }
}

function Save-Config {
    try {
        $c = Get-ConfigSnapshot
        $json = $c | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($configFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log 'Configuracion guardada'
    }
    catch { Write-Log "No se pudo guardar config.json: $_" }
}

# --- Reproductor incrustado (WebView2) -----------------------------------
# El reproductor vive dentro de la propia ventana. WebView2 usa el motor de
# Microsoft Edge ya presente en Windows 10/11; las DLLs del SDK se empaquetan
# en lib/webview2 para que la app siga siendo portable.
$script:WebViewLib       = Join-Path $scriptDir 'lib\webview2'
$script:WebViewData      = Join-Path $env:LOCALAPPDATA 'F1TrayMonitor\WebView2'
$script:WebViewProfile   = Join-Path $script:WebViewData 'profile'
$script:WebViewRoot      = Join-Path $script:WebViewData 'player'
$script:WebViewAvailable = $false
$script:WebViewFailed    = $false
$script:WebView          = $null
$script:WebViewCore      = $null
$script:WebViewReady     = $false
$script:WebViewInitTimer = $null
$script:WebViewEnvTask   = $null
$script:WebViewCoreTask  = $null
$script:WebViewStage     = 0
$script:WebViewPending   = $null
$script:BlockHosts       = @()
$script:BlockPatterns    = @()
$script:VideoOnly        = $false
$script:ListVisible      = $true
$script:WindowLayer      = 'normal'
$script:UpdateTask       = $null
$script:UpdateClient     = $null
$script:UpdateTimer      = $null
$script:UpdateBusy       = $false
$script:UpdateStatusText = ''
$script:LogForm          = $null
$script:SettingsUpdateStatus = $null
$script:SettingsUpdateLink   = $null
$script:SettingsMaintStatus   = $null
$script:SettingsMaintToggle   = $null
$script:SettingsVersionLbl    = $null

# --- Instancia unica ------------------------------------------------------
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\F1TrayMonitor_SingleInstance')
if (-not $script:mutex.WaitOne(0)) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

# Tipografias del listado. Bahnschrift da el aire condensado de las parrillas
# de F1; si no esta instalada, se cae a Segoe UI sin romper la interfaz.
function New-UiFont {
    param(
        [string[]]$Names,
        [float]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    foreach ($n in $Names) {
        try {
            $f = New-Object System.Drawing.Font($n, $Size, $Style)
            if ($f.Name -eq $n) { return $f }
            $f.Dispose()
        } catch { }
    }
    return New-Object System.Drawing.Font('Segoe UI', $Size, $Style)
}

$script:FontGp      = New-UiFont -Names @('Bahnschrift SemiBold Condensed','Bahnschrift SemiCondensed','Bahnschrift','Segoe UI Semibold') -Size 15.5 -Style ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic)
$script:FontNum     = New-UiFont -Names @('Bahnschrift','Segoe UI') -Size 18 -Style ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic)
$script:FontCc      = New-UiFont -Names @('Bahnschrift','Segoe UI') -Size 7.5 -Style ([System.Drawing.FontStyle]::Bold)
$script:FontChip    = New-UiFont -Names @('Segoe UI Semibold','Segoe UI') -Size 7.2 -Style ([System.Drawing.FontStyle]::Bold)
$script:FontCircuit = New-UiFont -Names @('Segoe UI Semibold','Segoe UI') -Size 8.2
$script:FontChevron = New-UiFont -Names @('Segoe UI Symbol','Segoe UI') -Size 12 -Style ([System.Drawing.FontStyle]::Bold)

# La primera ventana de un proceso lanzado con -WindowStyle Hidden nace oculta.
# Forzamos su visualizacion con ShowWindow.
if (-not ('F1.User32' -as [type])) {
    Add-Type -Namespace F1 -Name User32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
'@
}

if (-not ('F1.Dwm' -as [type])) {
    Add-Type -Namespace F1 -Name Dwm -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int attrValue, int attrSize);
'@
}

# Texto de ayuda dentro del cuadro de busqueda (EM_SETCUEBANNER) y tema oscuro
# para las barras de desplazamiento nativas de los paneles.
if (-not ('F1.Ui' -as [type])) {
    Add-Type -Namespace F1 -Name Ui -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessage(System.IntPtr hWnd, uint msg, System.IntPtr wParam, string lParam);
[System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetWindowTheme(System.IntPtr hWnd, string pszSubAppName, string pszSubIdList);
'@
}

# Ventana sin bordes pero redimensionable: se intercepta WM_NCHITTEST en el
# marco de 6 px y WM_GETMINMAXINFO para que maximizar respete la barra de
# tareas. Incluye utilidades para arrastrar la ventana desde la cabecera.
if (-not ('F1.ShellForm' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace F1
{
    public class ShellForm : Form
    {
        public int ResizeBorder = 6;
        public bool AllowResize = true;

        public ShellForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            DoubleBuffered = true;
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ResizeBorder = Math.Max(4, (int)Math.Round(6.0 * DeviceDpi / 96.0));
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        public struct MINMAXINFO
        {
            public POINT ptReserved;
            public POINT ptMaxSize;
            public POINT ptMaxPosition;
            public POINT ptMinTrackSize;
            public POINT ptMaxTrackSize;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0024) // WM_GETMINMAXINFO
            {
                base.WndProc(ref m);
                try
                {
                    MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(m.LParam, typeof(MINMAXINFO));
                    Rectangle wa = Screen.FromHandle(Handle).WorkingArea;
                    mmi.ptMaxPosition.X = wa.X;
                    mmi.ptMaxPosition.Y = wa.Y;
                    mmi.ptMaxSize.X = wa.Width;
                    mmi.ptMaxSize.Y = wa.Height;
                    Marshal.StructureToPtr(mmi, m.LParam, true);
                }
                catch { }
                return;
            }

            if (m.Msg == 0x0084 && AllowResize) // WM_NCHITTEST
            {
                base.WndProc(ref m);
                if ((int)m.Result == 1) // HTCLIENT
                {
                    int lp = m.LParam.ToInt32();
                    Point c = PointToClient(new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF)));
                    int b = ResizeBorder;
                    bool left = c.X <= b;
                    bool right = c.X >= ClientSize.Width - b;
                    bool top = c.Y <= b;
                    bool bottom = c.Y >= ClientSize.Height - b;
                    if (top && left) m.Result = (IntPtr)13;       // HTTOPLEFT
                    else if (top && right) m.Result = (IntPtr)14; // HTTOPRIGHT
                    else if (bottom && left) m.Result = (IntPtr)16;   // HTBOTTOMLEFT
                    else if (bottom && right) m.Result = (IntPtr)17;  // HTBOTTOMRIGHT
                    else if (left) m.Result = (IntPtr)10;         // HTLEFT
                    else if (right) m.Result = (IntPtr)11;        // HTRIGHT
                    else if (top) m.Result = (IntPtr)12;          // HTTOP
                    else if (bottom) m.Result = (IntPtr)15;       // HTBOTTOM
                }
                return;
            }

            base.WndProc(ref m);
        }
    }

    // Globo flotante sobre la bandeja: no roba el foco ni aparece en Alt+Tab.
    public class HintForm : Form
    {
        public HintForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            DoubleBuffered = true;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                const int WS_EX_TOOLWINDOW = 0x00000080;
                const int WS_EX_NOACTIVATE = 0x08000000;
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
                return cp;
            }
        }
    }

    public static class Native
    {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        // Captura una ventana (incluido su contenido DirectComposition, como
        // WebView2) aunque este tapada por otras ventanas.
        [DllImport("user32.dll")]
        public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);

        // Arrastra la ventana como si se hubiera pulsado su barra de titulo.
        public static void Drag(IntPtr hwnd)
        {
            ReleaseCapture();
            SendMessage(hwnd, 0x00A1, (IntPtr)2, IntPtr.Zero);
        }

        // Cambia la capa de la ventana: siempre encima, al fondo o normal.
        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
        public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
    }
}
'@
}


# Sin declararse DPI-aware: el diseno esta medido en pixeles de 96 ppp y Windows
# lo escala entero en equipos al 125-150 %. Declararlo dejaba el texto un 50 %
# mas grande que sus botones y recortaba etiquetas en Ajustes y en la cabecera.
# (Pendiente para 2.0: escalado por monitor v2 con todos los controles medidos.)

[System.Windows.Forms.Application]::EnableVisualStyles()

# Red de seguridad: una excepcion no controlada de la interfaz se registra y la
# app continua. Antes WinForms abria un cuadro modal que la dejaba bloqueada.
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    Write-Log ("UI: excepcion no controlada: {0}" -f $e.Exception.Message)
})

# --- Log ------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    try {
        if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 1MB)) {
            Move-Item $logFile "$logFile.old" -Force
        }
        Add-Content -Path $logFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }
}

# --- Datos ----------------------------------------------------------------
function Load-Posts {
    if (-not (Test-Path $dataFile)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($dataFile, [System.Text.Encoding]::UTF8)
        if (-not $raw -or -not $raw.Trim()) { return @() }
        return @($raw | ConvertFrom-Json)
    } catch {
        Write-Log "Error leyendo JSON: $_"
        return @()
    }
}

# --- Estado de la interfaz (paginacion) -----------------------------------
function Read-State {
    $script:NextPage = 2
    $script:SavedSearch = ''
    $script:TrayHintShown = 0
    $script:TrayRightClicked = $false
    $script:Favorites = @()
    $script:SearchHistory = @()
    $script:SplitRatio = 0.40
    $script:UpdateCheckedAt = ''
    $script:UpdateLatest = ''
    $script:UpdateUrl = ''
    if (-not (Test-Path $stateFile)) { return }
    try {
        $raw = [System.IO.File]::ReadAllText($stateFile, [System.Text.Encoding]::UTF8)
        if (-not $raw -or -not $raw.Trim()) { return }
        $st = $raw | ConvertFrom-Json
        if ($null -ne $st.nextPage) { $script:NextPage = [Math]::Max(2, [int]$st.nextPage) }
        if ($st.search) { $script:SavedSearch = [string]$st.search }
        if ($null -ne $st.trayHintShown) { $script:TrayHintShown = [Math]::Max(0, [int]$st.trayHintShown) }
        if ($null -ne $st.trayRightClicked) { $script:TrayRightClicked = [bool]$st.trayRightClicked }
        if ($st.sourcesFetchedAt) { $script:SourcesFetchedAt = [string]$st.sourcesFetchedAt }
        if ($st.favorites) { $script:Favorites = @($st.favorites | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
        if ($st.searchHistory) { $script:SearchHistory = @($st.searchHistory | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
        if ($st.updateCheckedAt) { $script:UpdateCheckedAt = [string]$st.updateCheckedAt }
        if ($st.updateLatest) { $script:UpdateLatest = [string]$st.updateLatest }
        if ($st.updateUrl) { $script:UpdateUrl = [string]$st.updateUrl }
        if ($null -ne $st.splitRatio) {
            $r = 0.0
            if ([double]::TryParse([string]$st.splitRatio, [ref]$r) -and $r -ge 0.10 -and $r -le 0.90) {
                $script:SplitRatio = $r
            }
        }
    } catch { }
}

function Save-State {
    try {
        $st = [PSCustomObject]@{
            nextPage         = [int]$script:NextPage
            search           = if ($script:Config.rememberSearch) { [string]$script:SearchQuery } else { '' }
            trayHintShown    = [int]$script:TrayHintShown
            trayRightClicked = [bool]$script:TrayRightClicked
            sourcesFetchedAt = [string]$script:SourcesFetchedAt
            favorites        = @($script:Favorites)
            searchHistory    = @($script:SearchHistory)
            updateCheckedAt  = [string]$script:UpdateCheckedAt
            updateLatest     = [string]$script:UpdateLatest
            updateUrl        = [string]$script:UpdateUrl
            splitRatio       = [Math]::Round([double]$script:SplitRatio, 3)
        }
        $json = $st | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($stateFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Write-Log "No se pudo guardar el estado: $_"
    }
}

# --- Busqueda inteligente -------------------------------------------------
# No compara solo caracteres: normaliza la consulta, la trocea en palabras y
# puntua cada entrada por titulo, tipo y fuentes, con sinonimos de Formula 1
# (paises, circuitos, sesiones, idiomas y plataformas), prefijos y tolerancia
# a erratas. Asi "interlagos" encuentra el GP de Brasil y "clasi" la
# clasificacion, sin escribir el titulo exacto.

$script:SearchStopWords = @(
    'de', 'del', 'la', 'el', 'los', 'las', 'un', 'una', 'unos', 'unas',
    'y', 'o', 'en', 'por', 'con', 'para', 'al', 'que',
    'the', 'of', 'and', 'to', 'in', 'on'
)

# Grupos de terminos equivalentes (ya normalizados: minusculas y sin tildes).
$script:SearchSynonymGroups = @(
    # Paises y circuitos
    @('mexico', 'cdmx', 'rodriguez', 'azteca'),
    @('brasil', 'brazil', 'interlagos', 'sao', 'paulo'),
    @('usa', 'eeuu', 'estados', 'unidos', 'austin', 'cota', 'miami', 'vegas'),
    @('canada', 'montreal', 'villeneuve'),
    @('inglaterra', 'britain', 'britanico', 'silverstone', 'uk'),
    @('italia', 'italy', 'monza', 'imola', 'mugello'),
    @('espana', 'spain', 'madrid', 'barcelona', 'catalunya', 'jerez'),
    @('monaco', 'montecarlo'),
    @('belgica', 'belgium', 'spa', 'francorchamps'),
    @('holanda', 'zandvoort', 'netherlands'),
    @('austria', 'spielberg', 'redbullring'),
    @('hungria', 'hungary', 'hungaroring'),
    @('azerbaiyan', 'baku', 'azerbaijan'),
    @('singapur', 'singapore', 'marinabay'),
    @('japon', 'japan', 'suzuka'),
    @('china', 'shanghai', 'shangai'),
    @('australia', 'melbourne', 'albertpark'),
    @('bahrein', 'bahrain', 'sakhir'),
    @('arabia', 'jeddah', 'yeda', 'saudita', 'saudi'),
    @('qatar', 'lusail', 'losail'),
    @('abudabi', 'yasmarina'),
    @('portugal', 'portimao', 'algarve'),
    @('francia', 'france', 'ricard', 'magny'),
    @('alemania', 'germany', 'hockenheim', 'nurburgring'),
    @('turquia', 'turkey', 'estambul', 'istanbul'),
    @('rusia', 'russia', 'sochi'),
    @('sudafrica', 'kyalami'),
    @('malasia', 'sepang'),
    @('corea', 'korea', 'yeongam'),
    @('india', 'buddh'),
    @('argentina', 'buenosaires'),
    # Sesiones
    @('clasificacion', 'qualy', 'quali', 'qualifying', 'pole', 'clasificatorio'),
    @('carrera', 'race'),
    @('sprint', 'shootout'),
    @('libres', 'practice', 'practica', 'practicas', 'entrenamientos', 'entrenamiento', 'entreno', 'fp1', 'fp2', 'fp3'),
    @('previa', 'previo', 'previous', 'preshow'),
    @('post', 'posterior', 'after', 'postshow'),
    # Idioma y calidad
    @('espanol', 'castellano', 'latino', 'spanish'),
    @('ingles', 'english'),
    @('720p', '720'),
    @('1080p', '1080', 'fullhd'),
    # Plataformas
    @('dazn'),
    @('espn'),
    @('f1tv', 'f1tvpro')
)

$script:SearchSynonyms = @{}
foreach ($group in $script:SearchSynonymGroups) {
    foreach ($term in $group) {
        if (-not $script:SearchSynonyms.ContainsKey($term)) {
            $script:SearchSynonyms[$term] = $group
        }
    }
}

function ConvertTo-SearchText {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text.ToLowerInvariant()
    $t = $t -replace 'á', 'a' -replace 'à', 'a' -replace 'ä', 'a' -replace 'â', 'a' -replace 'ã', 'a'
    $t = $t -replace 'é', 'e' -replace 'è', 'e' -replace 'ë', 'e' -replace 'ê', 'e'
    $t = $t -replace 'í', 'i' -replace 'ì', 'i' -replace 'ï', 'i' -replace 'î', 'i'
    $t = $t -replace 'ó', 'o' -replace 'ò', 'o' -replace 'ö', 'o' -replace 'ô', 'o' -replace 'õ', 'o'
    $t = $t -replace 'ú', 'u' -replace 'ù', 'u' -replace 'ü', 'u' -replace 'û', 'u'
    $t = $t -replace 'ñ', 'n' -replace 'ç', 'c'
    return $t
}

function Split-SearchTokens {
    param([string]$Text)
    if (-not $Text) { return @() }
    $raw = @($Text -split '[^a-z0-9]+')
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in $raw) {
        if (-not $t) { continue }
        if ($script:SearchStopWords -contains $t) { continue }
        if ($t.Length -lt 2 -and $t -notmatch '^\d$') { continue }
        if (-not $out.Contains($t)) { $out.Add($t) }
    }
    return $out.ToArray()
}

function Get-EditDistance {
    param([string]$A, [string]$B)

    $la = $A.Length
    $lb = $B.Length
    if ($la -eq 0) { return $lb }
    if ($lb -eq 0) { return $la }

    $prev = [int[]]::new($lb + 1)
    $cur  = [int[]]::new($lb + 1)
    for ($j = 0; $j -le $lb; $j++) { $prev[$j] = $j }

    for ($i = 1; $i -le $la; $i++) {
        $cur[0] = $i
        $ca = $A[$i - 1]
        for ($j = 1; $j -le $lb; $j++) {
            $cost = if ($ca -eq $B[$j - 1]) { 0 } else { 1 }
            $best = $prev[$j] + 1
            if (($cur[$j - 1] + 1) -lt $best) { $best = $cur[$j - 1] + 1 }
            if (($prev[$j - 1] + $cost) -lt $best) { $best = $prev[$j - 1] + $cost }
            $cur[$j] = $best
        }
        $swap = $prev
        $prev = $cur
        $cur = $swap
    }
    return $prev[$lb]
}

function Get-SearchTokenScore {
    param([string]$Token, [string[]]$Tokens, [string]$Haystack)

    $cands = $script:SearchSynonyms[$Token]
    if (-not $cands) {
        # "practica" o "clasifi" heredan el grupo de su forma completa.
        if ($Token.Length -ge 4) {
            foreach ($key in $script:SearchSynonyms.Keys) {
                if ($key.Length -ge 4 -and $key.StartsWith($Token)) {
                    $cands = $script:SearchSynonyms[$key]
                    break
                }
            }
        }
    }
    if (-not $cands) { $cands = @($Token) }

    $best = 0
    foreach ($t in $Tokens) {
        foreach ($c in $cands) {
            if ($t -eq $c) { return 100 }
            if ($t.Length -ge 3 -and $c.Length -ge 3 -and $t.StartsWith($c)) {
                if ($best -lt 75) { $best = 75 }
            }
        }
    }
    if ($best -gt 0) { return $best }
    if ($Haystack.Contains($Token)) { return 60 }

    # Tolerancia a erratas: una letra en palabras cortas, dos en las largas.
    if ($Token.Length -ge 4) {
        $max = if ($Token.Length -ge 7) { 2 } else { 1 }
        foreach ($t in $Tokens) {
            if ([Math]::Abs($t.Length - $Token.Length) -gt $max) { continue }
            if ((Get-EditDistance $t $Token) -le $max) { return 45 }
        }
    }
    return 0
}

function Build-SearchIndex {
    $script:SearchIndex = @{}
    foreach ($p in $script:Posts) {
        $parts = @([string]$p.title, [string]$p.type)
        foreach ($o in @($p.options)) { if ($o.name) { $parts += [string]$o.name } }
        $text = ConvertTo-SearchText ($parts -join ' ')
        $script:SearchIndex[[string]$p.id] = [PSCustomObject]@{
            text   = $text
            tokens = @(Split-SearchTokens $text)
        }
    }
    Build-RaceIndex
}

function Get-FilteredPosts {
    param([string]$Query)

    if (-not $Query) {
        if (-not $script:FavoritesOnly) { return @($script:Posts) }
        return @($script:Posts | Where-Object { Test-Favorite (Get-FavoriteKey $_) })
    }

    $tokens = @(Split-SearchTokens $Query)
    if ($tokens.Count -eq 0) {
        if (-not $script:FavoritesOnly) { return @($script:Posts) }
        return @($script:Posts | Where-Object { Test-Favorite (Get-FavoriteKey $_) })
    }

    $scored = New-Object System.Collections.ArrayList
    foreach ($p in $script:Posts) {
        if ($script:FavoritesOnly -and -not (Test-Favorite (Get-FavoriteKey $p))) { continue }
        $idx = $script:SearchIndex[[string]$p.id]
        if (-not $idx) { continue }

        $score = 0
        $matched = $true
        foreach ($token in $tokens) {
            $s = Get-SearchTokenScore -Token $token -Tokens $idx.tokens -Haystack $idx.text
            if ($s -le 0) { $matched = $false; break }
            $score += $s
        }
        if (-not $matched) { continue }

        # Frase completa: vale mas que las palabras sueltas.
        if ($idx.text.Contains($Query)) { $score += 200 }
        [void]$scored.Add([PSCustomObject]@{
            post  = $p
            score = $score
            id    = [string]$p.id
        })
    }

    $ordered = $scored | Sort-Object -Property `
        @{ Expression = { $_.score }; Descending = $true }, `
        @{ Expression = { $_.id }; Descending = $true }
    return @($ordered | ForEach-Object { $_.post })
}

function Get-VisiblePosts {
    return @(Get-FilteredPosts -Query $script:SearchQuery)
}

function Get-TypeBullet {
    # Glifo neutro compatible con Segoe UI: el color del tipo ya lo aporta la
    # barra lateral de cada tarjeta. Los emojis se veian como cajas en algunos
    # equipos y en capturas GDI.
    return [char]::ConvertFromUtf32(0x25CF)
}

function Get-TypeColor {
    param([string]$Type, [string]$Hex)
    if ($Hex -and $Hex -match '^#[0-9a-fA-F]{6}$') {
        try { return [System.Drawing.ColorTranslator]::FromHtml($Hex) } catch { }
    }
    switch -Regex ($Type) {
        '^Carrera'      { return [System.Drawing.Color]::FromArgb(225, 6, 0) }
        '^Clasificaci'  { return [System.Drawing.Color]::FromArgb(168, 85, 247) }
        '^Sprint'       { return [System.Drawing.Color]::FromArgb(245, 158, 11) }
        '^Libres'       { return [System.Drawing.Color]::FromArgb(56, 189, 248) }
        default         { return [System.Drawing.Color]::FromArgb(59, 130, 246) }
    }
}

function Get-ShortTitle {
    param([string]$Title)
    if (-not $Title) { return '(sin titulo)' }
    $t = $Title -replace '^\s*Descargar\s+', ''
    $t = $t -replace '\s+en\s+Espa[ñn]ol\s*$', ''
    $t = $t -replace '\s+', ' '
    if ($t.Length -gt 64) { $t = $t.Substring(0, 61) + '...' }
    return $t.Trim()
}

# --- Metadatos de carrera (estilo videojuego de F1) -----------------------
# Del titulo "Descargar Formula 1 GP Brasil 2026 Carrera en Espanol" se extrae
# el GP, el ano y la ronda del calendario. El circuito y el pais se resuelven
# con una tabla propia para pintar la ficha como una tarjeta de parrilla.

$script:GpAliases = @{
    'australia' = 'australia'; 'melbourne' = 'australia'; 'albertpark' = 'australia'
    'china' = 'china'; 'shanghai' = 'china'
    'japon' = 'japan'; 'japan' = 'japan'; 'suzuka' = 'japan'
    'bahrein' = 'bahrain'; 'bahrain' = 'bahrain'; 'sakhir' = 'bahrain'
    'bahreinenmalasia' = 'malaysia'; 'malasia' = 'malaysia'; 'malaysia' = 'malaysia'; 'sepang' = 'malaysia'
    'arabiasaudita' = 'saudi'; 'arabiasaudi' = 'saudi'; 'saudiarabia' = 'saudi'; 'jeddah' = 'saudi'
    'miami' = 'miami'; 'miamigp' = 'miami'
    'emiliaromagna' = 'emilia'; 'imola' = 'emilia'
    'monaco' = 'monaco'; 'montecarlo' = 'monaco'
    'espana' = 'spain'; 'spain' = 'spain'; 'barcelona' = 'spain'; 'catalunya' = 'spain'
    'canada' = 'canada'; 'montreal' = 'canada'; 'gillesvilleneuve' = 'canada'
    'austria' = 'austria'; 'spielberg' = 'austria'; 'redbullring' = 'austria'
    'reino unido' = 'britain'; 'reinounido' = 'britain'; 'granbretana' = 'britain'
    'greatbritain' = 'britain'; 'britain' = 'britain'; 'britanico' = 'britain'; 'silverstone' = 'britain'
    'belgica' = 'belgium'; 'belgium' = 'belgium'; 'spa' = 'belgium'; 'spafrancorchamps' = 'belgium'
    'hungria' = 'hungary'; 'hungary' = 'hungary'; 'hungaroring' = 'hungary'
    'paisesbajos' = 'netherlands'; 'netherlands' = 'netherlands'; 'zandvoort' = 'netherlands'; 'dutch' = 'netherlands'
    'italia' = 'italy'; 'italy' = 'italy'; 'monza' = 'italy'
    'azerbaiyan' = 'azerbaijan'; 'azerbaijan' = 'azerbaijan'; 'baku' = 'azerbaijan'
    'singapur' = 'singapore'; 'singapore' = 'singapore'; 'marinabay' = 'singapore'
    'usa' = 'usa'; 'eeuu' = 'usa'; 'estadosunidos' = 'usa'; 'austin' = 'usa'; 'cota' = 'usa'; 'americas' = 'usa'
    'mexico' = 'mexico'; 'mexicocity' = 'mexico'; 'hermanosrodriguez' = 'mexico'
    'brasil' = 'brazil'; 'brazil' = 'brazil'; 'interlagos' = 'brazil'; 'saopaulo' = 'brazil'; 'carlosPace' = 'brazil'
    'lasvegas' = 'lasvegas'; 'vegas' = 'lasvegas'
    'qatar' = 'qatar'; 'lusail' = 'qatar'
    'abudhabi' = 'abudhabi'; 'yasmarina' = 'abudhabi'; 'abudhabigp' = 'abudhabi'
    'madrid' = 'madrid'; 'madring' = 'madrid'
}

$script:GpCircuits = @{
    'australia'   = [PSCustomObject]@{ cc = 'AUS'; circuit = 'Albert Park';              city = 'Melbourne' }
    'china'       = [PSCustomObject]@{ cc = 'CHN'; circuit = 'Shanghai International';   city = 'Shanghai' }
    'japan'       = [PSCustomObject]@{ cc = 'JPN'; circuit = 'Suzuka International';     city = 'Suzuka' }
    'bahrain'     = [PSCustomObject]@{ cc = 'BHR'; circuit = 'Bahrain International';    city = 'Sakhir' }
    'saudi'       = [PSCustomObject]@{ cc = 'SAU'; circuit = 'Jeddah Corniche';          city = 'Jeddah' }
    'miami'       = [PSCustomObject]@{ cc = 'USA'; circuit = 'Miami International';      city = 'Miami' }
    'emilia'      = [PSCustomObject]@{ cc = 'ITA'; circuit = 'Enzo e Dino Ferrari';      city = 'Imola' }
    'monaco'      = [PSCustomObject]@{ cc = 'MON'; circuit = 'Circuit de Monaco';        city = 'Monte Carlo' }
    'spain'       = [PSCustomObject]@{ cc = 'ESP'; circuit = 'Barcelona-Catalunya';      city = 'Barcelona' }
    'canada'      = [PSCustomObject]@{ cc = 'CAN'; circuit = 'Gilles Villeneuve';        city = 'Montreal' }
    'austria'     = [PSCustomObject]@{ cc = 'AUT'; circuit = 'Red Bull Ring';            city = 'Spielberg' }
    'britain'     = [PSCustomObject]@{ cc = 'GBR'; circuit = 'Silverstone';             city = 'Silverstone' }
    'belgium'     = [PSCustomObject]@{ cc = 'BEL'; circuit = 'Spa-Francorchamps';        city = 'Spa' }
    'hungary'     = [PSCustomObject]@{ cc = 'HUN'; circuit = 'Hungaroring';              city = 'Budapest' }
    'netherlands' = [PSCustomObject]@{ cc = 'NED'; circuit = 'Circuit Zandvoort';        city = 'Zandvoort' }
    'italy'       = [PSCustomObject]@{ cc = 'ITA'; circuit = 'Autodromo Nazionale';      city = 'Monza' }
    'azerbaijan'  = [PSCustomObject]@{ cc = 'AZE'; circuit = 'Baku City Circuit';        city = 'Baku' }
    'singapore'   = [PSCustomObject]@{ cc = 'SGP'; circuit = 'Marina Bay';               city = 'Singapore' }
    'usa'         = [PSCustomObject]@{ cc = 'USA'; circuit = 'Circuit of the Americas';  city = 'Austin' }
    'mexico'      = [PSCustomObject]@{ cc = 'MEX'; circuit = 'Hermanos Rodriguez';       city = 'Mexico City' }
    'brazil'      = [PSCustomObject]@{ cc = 'BRA'; circuit = 'Jose Carlos Pace';         city = 'Interlagos' }
    'lasvegas'    = [PSCustomObject]@{ cc = 'USA'; circuit = 'Las Vegas Strip';          city = 'Las Vegas' }
    'qatar'       = [PSCustomObject]@{ cc = 'QAT'; circuit = 'Lusail International';     city = 'Lusail' }
    'abudhabi'    = [PSCustomObject]@{ cc = 'UAE'; circuit = 'Yas Marina Circuit';       city = 'Abu Dhabi' }
    'madrid'      = [PSCustomObject]@{ cc = 'ESP'; circuit = 'Madring';                  city = 'Madrid' }
    'malaysia'    = [PSCustomObject]@{ cc = 'MYS'; circuit = 'Sepang International';     city = 'Kuala Lumpur' }
}

# Calendario oficial para los anos que ya conocemos. Asi la ronda es correcta
# aunque el cache solo tenga las ultimas carreras de la temporada (2024).
$script:CalendarOrder = @{
    '2024' = @('bahrain','saudi','australia','japan','china','miami','emilia','monaco','canada','spain','austria','britain','hungary','belgium','netherlands','italy','azerbaijan','singapore','usa','mexico','brazil','lasvegas','qatar','abudhabi')
    '2025' = @('bahrain','saudi','australia','japan','china','miami','emilia','monaco','canada','spain','austria','britain','hungary','belgium','netherlands','italy','azerbaijan','singapore','usa','mexico','brazil','lasvegas','qatar','abudhabi')
}

$script:RaceRounds = @{}

function ConvertTo-Key {
    param([string]$Text)
    if (-not $Text) { return '' }
    $norm = $Text.ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return ($sb.ToString() -replace '[^a-z0-9]+', '')
}

function Build-RaceIndex {
    $script:RaceRounds = @{}
    $byYear = @{}

    foreach ($p in $script:Posts) {
        $m = [regex]::Match([string]$p.title, '(?i)\bGP\s+(.+?)\s+((?:19|20)\d{2})\b')
        if (-not $m.Success) { continue }
        $year = $m.Groups[2].Value
        $key = ConvertTo-Key $m.Groups[1].Value
        $canon = $script:GpAliases[$key]
        if (-not $canon) { $canon = $key }

        if (-not $byYear.ContainsKey($year)) { $byYear[$year] = @{} }
        $id = 0
        try { $id = [int]$p.id } catch { $id = 0 }
        if (-not $byYear[$year].ContainsKey($canon) -or $id -lt [int]$byYear[$year][$canon]) {
            $byYear[$year][$canon] = $id
        }
    }

    foreach ($year in $byYear.Keys) {
        $keys = @()
        if ($script:CalendarOrder.ContainsKey([string]$year)) {
            $keys = @($script:CalendarOrder[[string]$year])
        }
        else {
            # Ano desconocido: ordenar por la primera vez que aparece cada GP.
            $keys = @($byYear[$year].GetEnumerator() |
                Sort-Object -Property Value |
                ForEach-Object { $_.Key })
        }

        for ($i = 0; $i -lt $keys.Count; $i++) {
            if ($byYear[$year].ContainsKey($keys[$i])) {
                $script:RaceRounds["$year|$($keys[$i])"] = $i + 1
            }
        }

        $extra = @($byYear[$year].Keys | Where-Object { $keys -notcontains $_ })
        $n = $keys.Count
        foreach ($k in $extra) {
            $n++
            $script:RaceRounds["$year|$k"] = $n
        }
    }
}

function Get-RaceMeta {
    param([string]$Title)

    $fallback = [PSCustomObject]@{
        IsF1    = $false
        Gp      = (Get-ShortTitle $Title).ToUpperInvariant()
        GpKey   = (ConvertTo-Key (Get-ShortTitle $Title))
        Year    = ''
        Round   = ''
        Session = (Get-SessionKey $Title)
        Cc      = 'F1'
        Circuit = 'Evento especial'
        City    = ''
    }
    if (-not $Title) { return $fallback }

    $m = [regex]::Match($Title, '(?i)\bGP\s+(.+?)\s+((?:19|20)\d{2})\b')
    if (-not $m.Success) { return $fallback }

    $rawGp = ($m.Groups[1].Value -replace '\s+', ' ').Trim()
    $year = $m.Groups[2].Value
    $key = ConvertTo-Key $rawGp
    $canon = $script:GpAliases[$key]
    if (-not $canon) { $canon = $key }

    $info = $script:GpCircuits[$canon]
    $cc = 'F1'
    $circuit = 'Circuito por confirmar'
    $city = ''
    if ($info) {
        $cc = [string]$info.cc
        $circuit = [string]$info.circuit
        $city = [string]$info.city
    }

    $round = ''
    $rk = "$year|$canon"
    if ($script:RaceRounds.ContainsKey($rk)) { $round = [string]$script:RaceRounds[$rk] }

    return [PSCustomObject]@{
        IsF1    = $true
        Gp      = $rawGp.ToUpperInvariant()
        GpKey   = $canon
        Year    = $year
        Round   = $round
        Session = (Get-SessionKey $Title)
        Cc      = $cc
        Circuit = $circuit
        City    = $city
    }
}

# Clave de sesion normalizada: carrera, clasificacion, sprint, libres1...
function Get-SessionKey {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = ConvertTo-SearchText $Text
    if ($t -match 'sprint\s*shootout|shootout') { return 'sprintshootout' }
    if ($t -match '\bsprint\b') { return 'sprint' }
    if ($t -match 'clasificacion|qualy|quali|qualifying') { return 'clasificacion' }
    if ($t -match 'libres\s*3|\bfp3\b') { return 'libres3' }
    if ($t -match 'libres\s*2|\bfp2\b') { return 'libres2' }
    if ($t -match 'libres\s*1|\bfp1\b') { return 'libres1' }
    if ($t -match 'previa|previo|preshow') { return 'previa' }
    if ($t -match 'posterior|\bpost\b|postshow') { return 'post' }
    if ($t -match 'carrera|\brace\b') { return 'carrera' }
    return ''
}

# --- Favoritos ------------------------------------------------------------
# La clave sobrevive a los reescrapeos: se basa en ano, GP y sesion, no en el
# identificador temporal de la entrada.
function Get-FavoriteKey {
    param($Post)
    $meta = Get-RaceMeta -Title ([string]$Post.title)
    if ($meta.IsF1 -and $meta.Year) {
        return "race|$($meta.Year)|$($meta.GpKey)|$($meta.Session)"
    }
    return "post|$([string]$Post.id)"
}

function Test-Favorite {
    param([string]$Key)
    if (-not $Key) { return $false }
    return (@($script:Favorites) -contains $Key)
}

function Toggle-Favorite {
    param([string]$Key)

    if (-not $Key) { return }
    if (Test-Favorite $Key) {
        $script:Favorites = @($script:Favorites | Where-Object { $_ -ne $Key })
        Write-Log "Favorito quitado: $Key"
    }
    else {
        $script:Favorites = @(@($script:Favorites) + $Key)
        Write-Log "Favorito anadido: $Key"
    }
    Save-State
    Update-FavoriteStars
    if ($script:FavoritesOnly) { Build-List }
}

function Update-FavoriteFilterButton {
    if (-not $script:FavFilterBtn) { return }
    $on = [bool]$script:FavoritesOnly
    $script:FavFilterBtn.Text = if ($on) { [char]::ConvertFromUtf32(0x2605) } else { [char]::ConvertFromUtf32(0x2606) }
    $script:FavFilterBtn.ForeColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(220, 220, 232) }
}

function Update-FavoriteStars {
    # Incluye las tarjetas en cache que ahora no se ven, para que la estrella
    # aparezca correcta al volver a mostrarlas.
    $all = @($script:CardCache.Values)
    if ($all.Count -eq 0) { $all = @($script:Cards) }
    foreach ($c in $all) {
        if (-not $c.StarBtn) { continue }
        $on = Test-Favorite ([string]$c.FavKey)
        $c.StarBtn.Text = if ($on) { [char]::ConvertFromUtf32(0x2605) } else { [char]::ConvertFromUtf32(0x2606) }
        $c.StarBtn.ForeColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(125, 125, 140) }
    }
}

# --- Historial de busquedas ----------------------------------------------
function Add-SearchHistory {
    param([string]$Text)

    $q = ([string]$Text).Trim()
    if ($q.Length -lt 2) { return }
    if ($q.Length -gt 80) { $q = $q.Substring(0, 80) }
    $list = @($script:SearchHistory | Where-Object { $_ -ne $q })
    $script:SearchHistory = @(@($q) + $list | Select-Object -First 8)
    Save-State
}

function Remove-SearchHistory {
    param([string]$Text)
    $script:SearchHistory = @($script:SearchHistory | Where-Object { $_ -ne $Text })
    Save-State
}

# El catalogo permite publicar opciones nuevas sin volver a escrapear: reglas
# que casan por id, GP, ano, sesion o texto del titulo y anaden reproductores
# de servicios de streaming. Se puede alojar en GitHub y editar a mano.

function Read-SourcesCatalogFile {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if (-not $raw -or -not $raw.Trim()) { return $null }
        $cat = $raw | ConvertFrom-Json
        if ($null -eq $cat) { return $null }
        if (-not $cat.PSObject.Properties['rules']) {
            $cat | Add-Member -NotePropertyName rules -NotePropertyValue @() -Force
        }
        return $cat
    }
    catch {
        Write-Log "Catalogo: JSON no valido en $Path ($($_.Exception.Message))"
        return $null
    }
}

function Read-SourcesCatalog {
    $catalog = $null
    $from = ''

    # 1. Copia descargada (la mas reciente y la que puede editarse en GitHub).
    $catalog = Read-SourcesCatalogFile -Path $sourcesCacheFile
    if ($catalog) { $from = 'cache' }

    # 2. Copia incluida con la app (sirve de respaldo y de base editable).
    if (-not $catalog) {
        $catalog = Read-SourcesCatalogFile -Path $sourcesFile
        if ($catalog) { $from = 'local' }
    }

    $script:SourcesCatalog = $catalog
    if ($catalog) {
        $n = @($catalog.rules).Count
        Write-Log "Catalogo de fuentes: $from, $n reglas, version $($catalog.version)"
    }
    else {
        Write-Log 'Catalogo de fuentes: no disponible'
    }
    return $catalog
}

function Get-SourceService {
    param([string]$Key)

    if (-not $Key -or -not $script:SourcesCatalog) { return $null }
    $svc = $script:SourcesCatalog.services
    if (-not $svc) { return $null }
    $prop = $svc.PSObject.Properties[$Key]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-SourceRuleMatch {
    param($Rule, $Post)

    $match = $Rule.match
    if ($null -eq $match) { return $true }

    $props = @($match.PSObject.Properties | Where-Object { $_.Name -ne 'any' })
    if ($props.Count -eq 0) { return $true }

    $meta = Get-RaceMeta -Title ([string]$Post.title)
    $type = [string]$Post.type
    $title = ConvertTo-SearchText ([string]$Post.title)

    $has = $false
    if ($null -ne $match.id) {
        $has = $true
        if ([string]$Post.id -ne [string]$match.id) { return $false }
    }
    if ($null -ne $match.year) {
        $has = $true
        if ([string]$meta.Year -ne [string]$match.year) { return $false }
    }
    if ($match.gp) {
        $has = $true
        $want = ConvertTo-Key ([string]$match.gp)
        $wantCanon = $script:GpAliases[$want]
        if (-not $wantCanon) { $wantCanon = $want }
        if ($meta.IsF1) {
            if ([string]$meta.GpKey -ne $wantCanon -and -not ([string]$meta.Gp).ToLowerInvariant().Contains(([string]$match.gp).ToLowerInvariant())) { return $false }
        }
        elseif (-not $title.Contains($want)) { return $false }
    }
    if ($match.session) {
        $has = $true
        if ((Get-SessionKey ([string]$match.session)) -ne $meta.Session) { return $false }
    }
    if ($match.titleContains) {
        $has = $true
        if (-not $title.Contains((ConvertTo-SearchText ([string]$match.titleContains)))) { return $false }
    }
    if ($match.type) {
        $has = $true
        if (-not $type.ToLowerInvariant().Contains(([string]$match.type).ToLowerInvariant())) { return $false }
    }

    return $has
}

function New-PlayOption {
    param(
        [string]$Name,
        [string]$Url,
        [string]$ServiceKey = '',
        [string]$Quality = '',
        [string]$Lang = '',
        [string]$Origin = 'blog',
        [bool]$Primary = $false
    )

    $hint = Get-OptionHint -Name $Name -Url $Url
    if (-not $ServiceKey) { $ServiceKey = $hint.ServiceKey }
    if (-not $Quality) { $Quality = $hint.Quality }
    if (-not $Lang) { $Lang = $hint.Lang }

    $label = $ServiceKey
    $color = ''
    $svc = Get-SourceService -Key $ServiceKey
    if ($svc) {
        if ($svc.label) { $label = [string]$svc.label }
        if ($svc.color) { $color = [string]$svc.color }
    }
    if (-not $label) { $label = $hint.Service }

    return [PSCustomObject]@{
        name       = $Name
        player_url = $Url
        url        = $Url
        service    = $label
        serviceKey = $ServiceKey
        color      = $color
        quality    = $Quality
        lang       = $Lang
        origin     = $Origin
        primary    = $Primary
    }
}

function Get-OptionHint {
    param([string]$Name, [string]$Url)

    $text = ConvertTo-SearchText (([string]$Name) + ' ' + ([string]$Url))

    $serviceKey = ''
    $service = 'Blog'
    $services = @(
        @{ k = 'dazn';        re = 'dazn';              label = 'DAZN' },
        @{ k = 'espn';        re = 'espn';              label = 'ESPN' },
        @{ k = 'tnt';         re = 'tnt';               label = 'TNT Sports' },
        @{ k = 'sky';         re = 'sky';               label = 'Sky Sport' },
        @{ k = 'f1tv';        re = 'f1 ?tv|f1tv';       label = 'F1 TV' },
        @{ k = 'movistar';    re = 'movistar';          label = 'Movistar+' },
        @{ k = 'voe';         re = 'voe\.sx|voe';       label = 'VOE' },
        @{ k = 'streamtape';  re = 'streamtape';        label = 'Streamtape' },
        @{ k = 'doodstream';  re = 'doodstream|dood\.'; label = 'DoodStream' },
        @{ k = 'filemoon';    re = 'filemoon';          label = 'Filemoon' },
        @{ k = 'mixdrop';     re = 'mixdrop';           label = 'MixDrop' },
        @{ k = 'okru';        re = 'ok\.ru|okru';       label = 'OK.ru' }
    )
    foreach ($s in $services) {
        if ($text -match $s.re) { $serviceKey = $s.k; $service = $s.label; break }
    }

    $quality = ''
    if ($text -match '\b(2160p|4k|uhd)\b') { $quality = '4K' }
    elseif ($text -match '\b(1440p|2k)\b') { $quality = '1440p' }
    elseif ($text -match '\b1080p?\b|\bfullhd\b') { $quality = '1080p' }
    elseif ($text -match '\b720p?\b|\bhd\b') { $quality = '720p' }
    elseif ($text -match '\b480p?\b|\bsd\b') { $quality = '480p' }

    $lang = ''
    if ($text -match 'castellano|\bespanol\b|\bspanish\b|\bes\b') { $lang = 'ES' }
    elseif ($text -match 'latino|\blat\b') { $lang = 'LAT' }
    elseif ($text -match '\bingles\b|\benglish\b|\beng\b') { $lang = 'EN' }
    elseif ($text -match '\bvose\b|subtitulado') { $lang = 'VOSE' }

    return [PSCustomObject]@{
        ServiceKey = $serviceKey
        Service    = $service
        Quality    = $quality
        Lang       = $lang
    }
}

# Prioridad y caducidad de reglas del catalogo.
# priority alto gana; starts/expires aceptan fechas ISO 8601 (2026-11-15 o
# 2026-11-15T18:00:00+01:00). Una regla vencida se ignora sin borrarla.
function Get-RulePriority {
    param($Rule)
    if ($null -eq $Rule.priority) { return 0 }
    $n = 0
    if ([int]::TryParse([string]$Rule.priority, [ref]$n)) { return $n }
    return 0
}

function Test-RuleActive {
    param($Rule)

    $now = Get-Date
    if ($Rule.starts) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParse([string]$Rule.starts, [ref]$d) -and $now -lt $d) { return $false }
    }
    if ($Rule.expires) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParse([string]$Rule.expires, [ref]$d) -and $now -gt $d) { return $false }
    }
    return $true
}

# Devuelve las opciones de un post: las del blog + las del catalogo, sin
# duplicar URLs. Las del catalogo van primero porque suelen ser las curadas.
function Get-PlayOptions {
    param($Post)

    $list = New-Object System.Collections.ArrayList
    $seen = @{}
    $catalogAdded = 0

    if ($script:SourcesCatalog -and $script:Config.sourcesEnabled) {
        $rules = @($script:SourcesCatalog.rules | Where-Object { $_ } |
                Sort-Object -Property @{ Expression = { Get-RulePriority $_ }; Descending = $true })
        foreach ($rule in $rules) {
            if ($null -eq $rule) { continue }
            if ($null -ne $rule.enabled -and -not [bool]$rule.enabled) { continue }
            if (-not (Test-RuleActive $rule)) { continue }
            if (-not (Test-SourceRuleMatch -Rule $rule -Post $Post)) { continue }

            $first = $true
            foreach ($o in @($rule.options)) {
                if (-not $o) { continue }
                $url = [string]$o.url
                if (-not $url) { continue }
                $key = $url.Trim().ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true

                $primary = $false
                if ($null -ne $o.primary) { $primary = [bool]$o.primary }
                elseif ($first) { $primary = $true }

                $svc = [string]$o.service
                [void]$list.Add((New-PlayOption -Name ([string]$o.name) -Url $url -ServiceKey $svc `
                    -Quality ([string]$o.quality) -Lang ([string]$o.lang) -Origin 'catalog' -Primary $primary))
                $catalogAdded++
                $first = $false
            }
        }
    }

    foreach ($o in @($Post.options)) {
        if (-not $o) { continue }
        $url = [string]$o.player_url
        if (-not $url) { continue }
        $key = $url.Trim().ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$list.Add((New-PlayOption -Name ([string]$o.name) -Url $url -Origin 'blog'))
    }

    if ($catalogAdded -gt 0) {
        Write-Log "Fuentes: $catalogAdded del catalogo para [$($Post.type)] $($Post.title)"
    }
    return @($list)
}

function Start-SourcesDownload {
    param([switch]$Force)

    if (-not $script:Config.sourcesEnabled) { return }
    if ($script:SourcesProc) { return }

    $url = [string]$script:Config.sourcesUrl
    if (-not $url) { return }

    # Si la copia descargada es reciente, no hace falta ir a la red.
    if (-not $Force -and (Test-Path $sourcesCacheFile)) {
        try {
            $age = (Get-Date) - (Get-Item $sourcesCacheFile).LastWriteTime
            if ($age.TotalHours -lt [int]$script:Config.sourcesRefreshHours) { return }
        } catch { }
    }

    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path $curl)) { $curl = 'curl.exe' }

    try { Remove-Item $sourcesTmpFile -Force -ErrorAction SilentlyContinue } catch { }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $curl
        $psi.Arguments = @(
            '-fsSL', '--compressed', '--max-time', '20', '--retry', '1',
            '-H', '"User-Agent: F1TrayMonitor"',
            '-H', '"Cache-Control: no-cache"',
            '-o', ('"' + $sourcesTmpFile + '"'),
            ('"' + $url + '"')
        ) -join ' '
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $script:SourcesProc = [System.Diagnostics.Process]::Start($psi)
        Write-Log "Catalogo: descargando $url"
        Update-SourcesStatusLabel 'Descargando catálogo...'
    }
    catch {
        Write-Log "Catalogo: no se pudo descargar: $_"
        $script:SourcesProc = $null
        $script:SourcesManual = $false
        Update-SourcesStatusLabel 'No se pudo iniciar la descarga.'
        return
    }

    if (-not $script:SourcesTimer) {
        $script:SourcesTimer = New-Object System.Windows.Forms.Timer
        $script:SourcesTimer.Interval = 400
        $script:SourcesTimer.Add_Tick({ Complete-SourcesDownload })
    }
    $script:SourcesTimer.Start()
}

function Complete-SourcesDownload {
    $proc = $script:SourcesProc
    if (-not $proc) { if ($script:SourcesTimer) { $script:SourcesTimer.Stop() }; return }

    $done = $false
    try { $done = $proc.HasExited } catch { $done = $true }
    if (-not $done) { return }

    if ($script:SourcesTimer) { $script:SourcesTimer.Stop() }
    $code = -1
    try { $code = [int]$proc.ExitCode } catch { }
    $script:SourcesProc = $null

    if ($code -ne 0 -or -not (Test-Path $sourcesTmpFile)) {
        Write-Log "Catalogo: descarga fallida (exit=$code)"
        try { Remove-Item $sourcesTmpFile -Force -ErrorAction SilentlyContinue } catch { }
        if ($script:SourcesManual) {
            $script:SourcesManual = $false
            Update-SourcesStatusLabel 'Error al descargar. Se mantiene el catálogo anterior.'
            Show-Balloon -Title 'Catálogo de fuentes' -Text 'No se pudo descargar el catálogo. Se mantiene la última copia buena.' -Icon Warning
        }
        return
    }

    $catalog = Read-SourcesCatalogFile -Path $sourcesTmpFile
    if (-not $catalog) {
        Write-Log 'Catalogo: el archivo descargado no es valido; se conserva el anterior'
        try { Remove-Item $sourcesTmpFile -Force -ErrorAction SilentlyContinue } catch { }
        if ($script:SourcesManual) {
            $script:SourcesManual = $false
            Update-SourcesStatusLabel 'El JSON no es válido. Se mantiene el catálogo anterior.'
            Show-Balloon -Title 'Catálogo de fuentes' -Text 'El archivo descargado no es un JSON válido. Revisa la sintaxis.' -Icon Warning
        }
        return
    }

    try {
        if (Test-Path $sourcesCacheFile) {
            try { [System.IO.File]::Replace($sourcesTmpFile, $sourcesCacheFile, $null) }
            catch {
                [System.IO.File]::Copy($sourcesTmpFile, $sourcesCacheFile, $true)
                Remove-Item $sourcesTmpFile -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            [System.IO.File]::Move($sourcesTmpFile, $sourcesCacheFile)
        }
        $script:SourcesFetchedAt = (Get-Date).ToString('o')
        Save-State
        Read-SourcesCatalog
        Write-Log "Catalogo: actualizado ($(@($catalog.rules).Count) reglas, version $($catalog.version))"
        Refresh-SourceOptions
        if ($script:SourcesManual) {
            $script:SourcesManual = $false
            Update-SourcesStatusLabel
            Show-Balloon -Title 'Catálogo de fuentes' -Text ("Actualizado: {0} reglas y {1} servicios." -f (@($catalog.rules).Count), (@($catalog.services.PSObject.Properties).Count)) -Icon Info
        }
        else {
            Update-SourcesStatusLabel 'Catálogo actualizado automáticamente.'
        }
    }
    catch {
        Write-Log "Catalogo: no se pudo guardar la copia: $_"
        $script:SourcesManual = $false
        Update-SourcesStatusLabel 'No se pudo guardar la copia del catálogo.'
    }
}

# Reaplica el catalogo al listado y a la bandeja sin recargar el blog.
function Refresh-SourceOptions {
    if ($script:MainForm -and -not $script:MainForm.IsDisposed -and $script:MainForm.Visible) {
        Build-List
    }
    Update-StatusCounts
    if ($script:TrayMenu -and $script:TrayMenu.Visible) { Show-TrayMenu }
}

# --- Navegador por defecto ------------------------------------------------
# Devuelve la ruta del .exe del navegador predeterminado para http/https.
function Get-DefaultBrowserExe {
    try {
        $k = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
        if (Test-Path $k) {
            $progId = (Get-ItemProperty $k).ProgId
            if ($progId) {
                $cmdKey = "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command"
                if (Test-Path $cmdKey) {
                    $cmd = [string](Get-ItemProperty $cmdKey).'(default)'
                    $m = [regex]::Match($cmd, '^\s*"([^"]+\.exe)"')
                    if (-not $m.Success) { $m = [regex]::Match($cmd, '^\s*([^\s]+\.exe)') }
                    if ($m.Success -and (Test-Path $m.Groups[1].Value)) { return $m.Groups[1].Value }
                }
            }
        }
    } catch { }

    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $candidates = New-Object System.Collections.ArrayList
    if ($env:LOCALAPPDATA) { [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Opera\opera.exe')) }
    if ($env:ProgramFiles) { [void]$candidates.Add((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')) }
    if ($pf86) { [void]$candidates.Add((Join-Path $pf86 'Google\Chrome\Application\chrome.exe')) }
    if ($env:ProgramFiles) { [void]$candidates.Add((Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')) }
    if ($pf86) { [void]$candidates.Add((Join-Path $pf86 'Microsoft\Edge\Application\msedge.exe')) }
    if ($env:ProgramFiles) { [void]$candidates.Add((Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe')) }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Get-OperaExe {
    $candidates = New-Object System.Collections.ArrayList
    if ($env:LOCALAPPDATA) { [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Opera\opera.exe')) }
    if ($env:ProgramFiles) { [void]$candidates.Add((Join-Path $env:ProgramFiles 'Opera\opera.exe')) }
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($pf86) { [void]$candidates.Add((Join-Path $pf86 'Opera\opera.exe')) }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $def = Get-DefaultBrowserExe
    if ($def -and ([System.IO.Path]::GetFileName($def) -match '^opera')) { return $def }
    return $null
}

# --- Reproductor ----------------------------------------------------------
# Se genera un HTML temporal con los datos ya incrustados. Asi NO se usa una
# URL "file:///...html?src=..." (Windows no resuelve bien la asociacion cuando
# hay query string).
#
# Opera, con el perfil normal y muchas pestanas, abre la pagina en una pestana
# en SEGUNDO plano: el usuario pulsa una opcion y "no pasa nada". Por eso se
# lanza una instancia aparte con su propio perfil y --new-window: esa SI crea
# una ventana visible y su titulo empieza por "F1 >" (lo pone player.html).
# Despues solo hay que localizar esa ventana nueva y traerla al primer plano.
# No se simulan clicks ni atajos de teclado.

if (-not ('F1.Win' -as [type])) {
    Add-Type -Namespace F1 -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
static extern bool EnumWindows(EnumWindowsProc cb, System.IntPtr p);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
static extern int GetWindowText(System.IntPtr h, System.Text.StringBuilder s, int n);
[System.Runtime.InteropServices.DllImport("user32.dll")]
static extern bool IsWindowVisible(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")]
static extern uint GetWindowThreadProcessId(System.IntPtr h, System.IntPtr p);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool BringWindowToTop(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr h, int n);
[System.Runtime.InteropServices.DllImport("user32.dll")]
static extern bool SystemParametersInfo(uint accion, uint p1, ref uint p2, uint p3);
public delegate bool EnumWindowsProc(System.IntPtr h, System.IntPtr p);
public static System.IntPtr[] FindAllByPrefix(string prefix) {
    var list = new System.Collections.Generic.List<System.IntPtr>();
    EnumWindows(delegate(System.IntPtr h, System.IntPtr p) {
        if (!IsWindowVisible(h)) return true;
        var sb = new System.Text.StringBuilder(512);
        GetWindowText(h, sb, 512);
        if (sb.Length > 0 && sb.ToString().StartsWith(prefix, System.StringComparison.OrdinalIgnoreCase)) {
            list.Add(h);
        }
        return true;
    }, System.IntPtr.Zero);
    return list.ToArray();
}
public static System.IntPtr FindByPrefix(string prefix) {
    System.IntPtr[] all = FindAllByPrefix(prefix);
    return all.Length > 0 ? all[0] : System.IntPtr.Zero;
}
public static bool Force(System.IntPtr h) {
    if (h == System.IntPtr.Zero) return false;
    if (GetForegroundWindow() == h) return true;
    // Windows bloquea el cambio de primer plano si la app no esta activa.
    uint cero = 0;
    SystemParametersInfo(0x2003, 0, ref cero, 0);   // SPI_SETFOREGROUNDLOCKTIMEOUT
    if (TryForeground(h)) return true;
    // Plan B: minimizar y restaurar desbloquea el cambio en Windows.
    ShowWindow(h, 6);                                // SW_MINIMIZE
    System.Threading.Thread.Sleep(120);
    ShowWindow(h, 9);                                // SW_RESTORE
    System.Threading.Thread.Sleep(120);
    return TryForeground(h);
}
static bool TryForeground(System.IntPtr h) {
    System.IntPtr fg = GetForegroundWindow();
    uint fgT = fg == System.IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, System.IntPtr.Zero);
    uint tgT = GetWindowThreadProcessId(h, System.IntPtr.Zero);
    if (fgT != 0 && tgT != 0 && fgT != tgT) AttachThreadInput(fgT, tgT, true);
    bool ok = SetForegroundWindow(h);
    if (!ok) { BringWindowToTop(h); ok = SetForegroundWindow(h); }
    if (fgT != 0 && tgT != 0 && fgT != tgT) AttachThreadInput(fgT, tgT, false);
    return GetForegroundWindow() == h;
}
'@
}

# --- Reproductor incrustado ------------------------------------------------
# Carga perezosa de las DLL del SDK. Si el runtime de WebView2 no esta
# instalado o las DLL faltan, la app sigue funcionando con el modo externo.
function Initialize-WebView2 {
    if ($script:WebViewAvailable) { return $true }
    if ($script:WebViewFailed) { return $false }

    try {
        $coreDll  = Join-Path $script:WebViewLib 'Microsoft.Web.WebView2.Core.dll'
        $formsDll = Join-Path $script:WebViewLib 'Microsoft.Web.WebView2.WinForms.dll'
        if (-not (Test-Path $coreDll) -or -not (Test-Path $formsDll)) {
            throw "Faltan las DLL de WebView2 en $($script:WebViewLib)"
        }

        # WebView2Loader.dll se resuelve por nombre: su carpeta debe estar en PATH.
        if ($env:PATH -notlike "*$($script:WebViewLib)*") {
            $env:PATH = "$($script:WebViewLib);$env:PATH"
        }
        if (-not ('Microsoft.Web.WebView2.Core.CoreWebView2Environment' -as [type])) {
            Add-Type -Path $coreDll
        }
        if (-not ('Microsoft.Web.WebView2.WinForms.WebView2' -as [type])) {
            Add-Type -Path $formsDll
        }

        $ver = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()
        if (-not $ver) { throw 'WebView2 Runtime no instalado' }

        $script:WebViewAvailable = $true
        Write-Log "WebView2 disponible: $ver"
        return $true
    }
    catch {
        $script:WebViewFailed = $true
        Write-Log "WebView2 no disponible: $($_.Exception.Message)"
        return $false
    }
}

# Hosts publicitarios extraidos de las mismas reglas que usa la extension de
# Opera, para que el bloqueo sea identico en ambos modos.
function Get-BlockedHosts {
    $list = New-Object System.Collections.Generic.List[string]
    try {
        $rulesPath = Join-Path $extensionDir 'rules.json'
        if (Test-Path $rulesPath) {
            $rules = Get-Content $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($r in $rules) {
                $filter = [string]$r.condition.urlFilter
                if ($filter -match '^\|\|([^\^/]+)') {
                    $h = $matches[1].Trim().ToLowerInvariant()
                    if ($h -and -not $list.Contains($h)) { $list.Add($h) }
                }
            }
        }
    }
    catch { Write-Log "No se pudieron leer las reglas de bloqueo: $_" }
    return $list.ToArray()
}

# Patrones de ruta (por ejemplo /popunder, /prebid o /vast). Se aplican solo
# a subrecursos: nunca bloquean la navegacion principal del reproductor.
function Get-BlockedPatterns {
    $list = New-Object System.Collections.Generic.List[string]
    try {
        $rulesPath = Join-Path $extensionDir 'rules.json'
        if (Test-Path $rulesPath) {
            $rules = Get-Content $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($r in $rules) {
                $filter = [string]$r.condition.urlFilter
                if (-not $filter -or $filter.StartsWith('||')) { continue }
                $f = $filter.Trim().ToLowerInvariant()
                if ($f -and $f -ne '*' -and -not $list.Contains($f)) { $list.Add($f) }
            }
        }
    }
    catch { Write-Log "No se pudieron leer los patrones de bloqueo: $_" }
    return $list.ToArray()
}

function New-EmbeddedWebView {
    param($HostPanel)
    if (-not (Initialize-WebView2)) { return $null }

    try {
        New-Item -ItemType Directory -Path $script:WebViewProfile -Force | Out-Null
        New-Item -ItemType Directory -Path $script:WebViewRoot -Force | Out-Null
        Copy-Item -LiteralPath $playerHtml -Destination (Join-Path $script:WebViewRoot 'player.html') -Force

        $wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $wv.Dock = 'Fill'
        $wv.DefaultBackgroundColor = [System.Drawing.Color]::FromArgb(5, 5, 10)
        $HostPanel.Controls.Add($wv)
        # El marcador de "Selecciona una opción" se añadió antes al mismo panel:
        # si no se retira, queda delante del WebView y tapa el reproductor.
        if ($script:VideoPlaceholder) { $script:VideoPlaceholder.Visible = $false }
        $wv.BringToFront()
        $script:WebView = $wv
        $script:BlockHosts = @(Get-BlockedHosts)
        $script:BlockPatterns = @(Get-BlockedPatterns)
        Start-WebViewInit
        return $wv
    }
    catch {
        $script:WebViewFailed = $true
        Write-Log "No se pudo crear WebView2: $($_.Exception.Message)"
        return $null
    }
}

function Start-WebViewInit {
    if (-not $script:WebView) { return }
    if ($script:WebViewInitTimer) { return }
    $script:WebViewStage = 0
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 120
    $timer.Add_Tick({ Step-WebViewInit })
    $script:WebViewInitTimer = $timer
    $timer.Start()
}

# Maquina de estados sin bucles de mensajes anidados: cada tick comprueba si
# la tarea asincrona de WebView2 ha terminado.
function Step-WebViewInit {
    $timer = $script:WebViewInitTimer
    $wv = $script:WebView
    if (-not $wv -or $wv.IsDisposed) { if ($timer) { $timer.Stop() }; return }

    try {
        switch ($script:WebViewStage) {
            0 {
                $script:WebViewStage = 1
                $envOpts = $null
                try {
                    $envOpts = New-Object Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions
                    # Autoplay sin gesto y sin throttling en segundo plano: el
                    # video arranca solo y no se congela al cambiar de ventana.
                    $envOpts.AdditionalBrowserArguments = '--autoplay-policy=no-user-gesture-required --disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows'
                } catch { $envOpts = $null }
                $script:WebViewEnvTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $script:WebViewProfile, $envOpts)
                break
            }
            1 {
                $t = $script:WebViewEnvTask
                if ($t -and $t.IsCompleted) {
                    if ($t.IsFaulted) { throw $t.Exception.GetBaseException() }
                    $script:WebViewStage = 2
                    $script:WebViewCoreTask = $wv.EnsureCoreWebView2Async($t.Result)
                }
                break
            }
            2 {
                $t = $script:WebViewCoreTask
                if ($t -and $t.IsCompleted) {
                    if ($t.IsFaulted) { throw $t.Exception.GetBaseException() }
                    $timer.Stop()
                    $script:WebViewStage = 3
                    Configure-WebView2
                }
                break
            }
        }
    }
    catch {
        if ($timer) { $timer.Stop() }
        $script:WebViewFailed = $true
        Write-Log "WebView2: fallo al inicializar: $($_.Exception.Message)"
    }
}

function Configure-WebView2 {
    $wv = $script:WebView
    $core = $wv.CoreWebView2
    $script:WebViewCore = $core

    $s = $core.Settings
    $s.AreDefaultContextMenusEnabled = $false
    $s.AreDevToolsEnabled = $false
    $s.IsStatusBarEnabled = $false
    $s.IsZoomControlEnabled = $false
    $s.AreBrowserAcceleratorKeysEnabled = $false
    $s.IsSwipeNavigationEnabled = $false
    $s.IsPasswordAutosaveEnabled = $false
    $s.IsGeneralAutofillEnabled = $false

    # Host virtual: solo se expone la carpeta que contiene player.html.
    $core.SetVirtualHostNameToFolderMapping(
        'f1player.local',
        $script:WebViewRoot,
        [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow)

    # Bloqueo de anuncios por host y por patron de ruta (mismas reglas que la extension).
    $core.AddWebResourceRequestedFilter('*', [Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext]::All)
    $core.Add_WebResourceRequested({
        param($sender, $e)
        try {
            $uri = [uri]$e.Request.Uri
            $h = $uri.Host.ToLowerInvariant()
            $full = $uri.AbsoluteUri.ToLowerInvariant()
            foreach ($d in $script:BlockHosts) {
                if ($h -eq $d -or $h.EndsWith('.' + $d)) {
                    $e.Response = $sender.Environment.CreateWebResourceResponse([System.IO.Stream]::Null, 403, 'Blocked', '')
                    return
                }
            }
            foreach ($p in $script:BlockPatterns) {
                if ($full.Contains($p)) {
                    $e.Response = $sender.Environment.CreateWebResourceResponse([System.IO.Stream]::Null, 403, 'Blocked', '')
                    return
                }
            }
        } catch { }
    })

    # Navegacion principal: solo http(s). Los intentos de saltar a una app,
    # a un esquema raro o a un host publicitario se cancelan en seco.
    $core.Add_NavigationStarting({
        param($sender, $e)
        try {
            $uri = [uri]$e.Uri
            $scheme = $uri.Scheme.ToLowerInvariant()
            if ($scheme -ne 'http' -and $scheme -ne 'https' -and $scheme -ne 'about') {
                $e.Cancel = $true
                Write-Log "WebView2: navegacion bloqueada ($scheme): $($e.Uri)"
                return
            }
            $h = $uri.Host.ToLowerInvariant()
            foreach ($d in $script:BlockHosts) {
                if ($h -eq $d -or $h.EndsWith('.' + $d)) {
                    $e.Cancel = $true
                    Write-Log "WebView2: navegacion a anunciante bloqueada: $h"
                    return
                }
            }
        } catch { }
    })

    # Sin ventanas emergentes, descargas ni permisos del navegador.
    $core.Add_NewWindowRequested({
        param($sender, $e)
        $e.Handled = $true
    })
    $core.Add_DownloadStarting({
        param($sender, $e)
        $e.Cancel = $true
    })
    $core.Add_PermissionRequested({
        param($sender, $e)
        $e.State = [Microsoft.Web.WebView2.Core.CoreWebView2PermissionState]::Deny
    })

    # Mensajes enviados por el deck HTML (botones de la ventana y del video).
    $core.Add_WebMessageReceived({
        param($sender, $e)
        try {
            $raw = $e.WebMessageAsJson
            if (-not $raw) { return }
            $msg = $raw | ConvertFrom-Json
            switch ([string]$msg.type) {
                'showList'     { Set-VideoOnly -Enabled $false; Set-ListVisible -Visible $true }
                'hideList'     { Set-VideoOnly -Enabled $true }
                'toggleList'   { Set-VideoOnly -Enabled (-not $script:VideoOnly) }
                'minimize'     { if ($script:MainForm) { $script:MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized } }
                'maximize'     { Toggle-Maximize }
                'close'        { if ($script:MainForm) { $script:MainForm.Hide() } }
                'drag'         { if ($script:MainForm) { [F1.Native]::Drag($script:MainForm.Handle) } }
                'layer'        { Cycle-WindowLayer }
                'openExternal' { if ($msg.url) { Start-Process ([string]$msg.url) } }
            }
        }
        catch { Write-Log "WebView2: mensaje no valido: $_" }
    })

    $core.Add_NavigationCompleted({
        param($sender, $e)
        if ($e.IsSuccess) {
            $script:WebViewReady = $true
            Write-Log 'WebView2: reproductor listo'
            Notify-WebViewVideoOnly
            Apply-Neon
            if ($script:WebViewPending) { Send-PlayerPayload }
        }
        else {
            Write-Log "WebView2: navegacion fallida (status=$($e.WebErrorStatus))"
        }
    })

    # Limpiador inyectado en todos los frames antes de que cargue el sitio.
    try {
        $cleaner = Join-Path $extensionDir 'cleaner.js'
        if (Test-Path $cleaner) {
            $js = [System.IO.File]::ReadAllText($cleaner, [System.Text.Encoding]::UTF8)
            [void]$core.AddScriptToExecuteOnDocumentCreatedAsync($js)
        }
        $cleanerCss = Join-Path $extensionDir 'cleaner.css'
        if (Test-Path $cleanerCss) {
            $css = [System.IO.File]::ReadAllText($cleanerCss, [System.Text.Encoding]::UTF8)
            $cssJs = "try{var s=document.createElement('style');s.textContent=" + ($css | ConvertTo-Json -Compress) + ";document.documentElement.appendChild(s);}catch(e){}"
            [void]$core.AddScriptToExecuteOnDocumentCreatedAsync($cssJs)
        }
    }
    catch { Write-Log "WebView2: no se pudo inyectar el limpiador: $_" }

    $core.Navigate('https://f1player.local/player.html')
}

function Send-PlayerPayload {
    $p = $script:WebViewPending
    if (-not $p) { return }
    if (-not $script:WebViewCore -or -not $script:WebViewReady) { return }

    try {
        $json = $p | ConvertTo-Json -Depth 6 -Compress
        $json = $json.Replace('<', '\u003c')
        [void]$script:WebViewCore.ExecuteScriptAsync("window.F1Player && window.F1Player.load($json);")
        Write-Log "WebView2: cargando [$($p.option)] -> $($p.src)"
    }
    catch { Write-Log "WebView2: no se pudo enviar el video: $_" }
}

# Avisa al deck HTML de que la ventana esta (o no) en modo solo video, para
# que muestre los controles de arrastrar/minimizar/cerrar.
function Notify-WebViewVideoOnly {
    if (-not $script:WebViewCore -or -not $script:WebViewReady) { return }
    try {
        $flag = if ($script:VideoOnly) { 'true' } else { 'false' }
        [void]$script:WebViewCore.ExecuteScriptAsync("window.F1Player && window.F1Player.setVideoOnly($flag);")
    }
    catch { }
}

function Show-EmbeddedPlayer {
    param(
        [string]$Src,
        [string]$Title,
        [string]$Option,
        [string]$Type = '',
        [object[]]$Sources = @()
    )

    if (-not $Src) { return }

    $srcList = @()
    foreach ($item in @($Sources)) {
        if ($null -eq $item) { continue }
        $srcList += [PSCustomObject]@{
            name = [string]$item.name
            url  = [string]$item.url
        }
    }

    $script:WebViewPending = [PSCustomObject]@{
        src      = $Src
        title    = $Title
        option   = $Option
        type     = $Type
        sources  = @($srcList)
        embedded = $true
        neon     = [string]$script:Config.neonTeam
        layer    = [string]$script:WindowLayer
    }

    Show-MainWindow
    Set-VideoOnly -Enabled $false
    Set-ListVisible -Visible $true
    if ($script:VideoOnlyBtn) { $script:VideoOnlyBtn.Enabled = $true }
    if ($script:WebViewReady) {
        Send-PlayerPayload
        if ($script:Config.openVideoOnly) { Set-VideoOnly -Enabled $true }
    }
}

# --- Ventana: lista y modo solo video -------------------------------------
function Set-ListVisible {
    param([bool]$Visible)

    $script:ListVisible = $Visible
    if ($script:Split -and -not $script:Split.IsDisposed) {
        if ($script:VideoOnly) { $script:Split.Panel1Collapsed = $true }
        else {
            $script:Split.Panel1Collapsed = -not $Visible
            if ($Visible) { Set-SplitRatio $script:SplitRatio }
        }
    }
    if ($script:ListToggleBtn) {
        $script:ListToggleBtn.Text = if ($Visible) { 'Ocultar lista' } else { 'Mostrar lista' }
    }
}

function Set-VideoOnly {
    param([bool]$Enabled)

    $script:VideoOnly = $Enabled
    if (-not $script:Layout) { return }

    if ($Enabled) {
        $script:Layout.RowStyles[0].Height = 0
        $script:Layout.RowStyles[1].Height = 0
        $script:Layout.RowStyles[3].Height = 0
        if ($script:Header)  { $script:Header.Visible = $false }
        if ($script:Toolbar) { $script:Toolbar.Visible = $false }
        if ($script:Footer)  { $script:Footer.Visible = $false }
        if ($script:Split)   { $script:Split.Panel1Collapsed = $true }
        Write-Log 'Ventana: modo solo video'
    }
    else {
        $script:Layout.RowStyles[0].Height = 64
        $script:Layout.RowStyles[1].Height = 44
        $script:Layout.RowStyles[3].Height = 26
        if ($script:Header)  { $script:Header.Visible = $true }
        if ($script:Toolbar) { $script:Toolbar.Visible = $true }
        if ($script:Footer)  { $script:Footer.Visible = $true }
        if ($script:Split)   { $script:Split.Panel1Collapsed = -not $script:ListVisible }
    }

        if ($script:MainForm -and -not $script:MainForm.IsDisposed) { $script:MainForm.PerformLayout() }
    Notify-WebViewVideoOnly
    try {
        if ($script:Split) {
            Write-Log ("VideoOnly: collapsed=$($script:Split.Panel1Collapsed) split=$($script:Split.Width)x$($script:Split.Height) p1=$($script:Split.Panel1.Width) p2=$($script:Split.Panel2.Width)")
        }
        if ($script:WebView) {
            Write-Log ("VideoOnly: webview=$($script:WebView.Width)x$($script:WebView.Height)")
        }
    } catch { }
}

function Toggle-Maximize {
    $form = $script:MainForm
    if (-not $form -or $form.IsDisposed) { return }
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    else {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
    }
}

# --- Reproductor: selector de modo ----------------------------------------
function Open-Player {
    param(
        [string]$Src,
        [string]$Title,
        [string]$Option,
        [string]$Type = '',
        [object[]]$Sources = @()
    )

    Write-Log "Open-Player entrada: src=[$Src] option=[$Option] modo=$($script:Config.playerMode)"
    if (-not $Src) { Write-Log 'Open-Player: sin src, se cancela'; return }

    if ($script:Config.playerMode -ne 'external' -and (Initialize-WebView2)) {
        try {
            Show-EmbeddedPlayer -Src $Src -Title $Title -Option $Option -Type $Type -Sources $Sources
            if ($script:WebView -and -not $script:WebView.IsDisposed) { return }
        }
        catch { Write-Log "Reproductor incrustado: fallo: $_" }
        Write-Log 'Reproductor incrustado no disponible; se usa el modo externo'
    }

    Open-PlayerExternal -Src $Src -Title $Title -Option $Option -Type $Type
}

function Open-PlayerExternal {
    param([string]$Src, [string]$Title, [string]$Option, [string]$Type = '')

    Write-Log "Open-Player entrada: src=[$Src] option=[$Option]"
    if (-not $Src) { Write-Log 'Open-Player: sin src, se cancela'; return }
    try {
        $template = [System.IO.File]::ReadAllText($playerHtml, [System.Text.Encoding]::UTF8)
        $payload = @{ src = $Src; title = $Title; option = $Option; type = $Type } | ConvertTo-Json -Compress
        $payload = $payload.Replace('<', '\u003c')
        # Debe inyectarse ANTES del script del reproductor (en <head>).
        $inject = "<script>window.__F1=$payload;</script>"
        $html = $template.Replace('<head>', "<head>`r`n$inject")

        $file = Join-Path $env:TEMP ("f1-player-{0}.html" -f ([guid]::NewGuid().ToString('N')))
        [System.IO.File]::WriteAllText($file, $html, (New-Object System.Text.UTF8Encoding($false)))
        $url = 'file:///' + ($file -replace '\\', '/')
        $script:PlayerUrl = $url

        if (-not $script:BrowserExe) { $script:BrowserExe = Get-DefaultBrowserExe }
        $browser = $script:BrowserExe
        $browserName = if ($browser) { [System.IO.Path]::GetFileNameWithoutExtension($browser).ToLowerInvariant() } else { '' }

        # Ventanas del reproductor que ya existian antes de este click.
        $script:PlayerMarker = 'F1 ' + [char]::ConvertFromUtf32(0x25B8)
        $script:PlayerBefore = @([F1.Win]::FindAllByPrefix($script:PlayerMarker))
        $script:PlayerFallback = $false
        $script:PlayerAttempts = 0

        Write-Log "Abriendo reproductor: $Option -> $Src"
        $opera = Get-OperaExe
        $useOpera = ($opera -and $script:Config.playerBrowser -ne 'default')

        if ($useOpera) {
            # Instancia propia: ventana visible garantizada, titulo detectable y
            # perfil aislado donde se carga la extension de limpieza.
            $playerProfile = Join-Path $env:LOCALAPPDATA 'F1TrayMonitor\PlayerProfile'
            New-Item -ItemType Directory -Path $playerProfile -Force | Out-Null

            $argLine = '--user-data-dir="{0}" --new-window --start-maximized --no-first-run --no-default-browser-check' -f $playerProfile
            $clean = [bool]$script:Config.cleanPlayer
            if ($clean -and (Test-Path (Join-Path $extensionDir 'manifest.json'))) {
                $argLine += ' --load-extension="{0}"' -f $extensionDir
            }
            $argLine += ' "{0}"' -f $url

            Start-Process -FilePath $opera -ArgumentList $argLine
            if ($clean) { Write-Log "Navegador: $opera (perfil del reproductor + limpieza)" }
            else { Write-Log "Navegador: $opera (perfil del reproductor)" }
        }
        elseif ($browser) {
            $browserArgs = if ($browserName -match 'firefox') { @('-new-window', $url) } else { @('--new-window', $url) }
            Start-Process -FilePath $browser -ArgumentList $browserArgs
            Write-Log "Navegador: $browser"
        }
        else {
            # Ultimo recurso: asociacion del sistema.
            Start-Process $url
            Write-Log 'Navegador: asociacion del sistema'
        }

        # Traer al primer plano la ventana NUEVA del reproductor en cuanto exista.
        if (-not $script:PlayerTimer) {
            $script:PlayerTimer = New-Object System.Windows.Forms.Timer
            $script:PlayerTimer.Interval = 400
            $script:PlayerTimer.Add_Tick({
                $script:PlayerAttempts++
                $todas = @([F1.Win]::FindAllByPrefix($script:PlayerMarker))
                $nuevas = @($todas | Where-Object { $script:PlayerBefore -notcontains $_ })
                if ($nuevas.Count -gt 0) {
                    $script:PlayerTimer.Stop()
                    [void][F1.Win]::Force($nuevas[0])
                    $fg = ([F1.Win]::GetForegroundWindow() -eq $nuevas[0])
                    Write-Log "Reproductor en primer plano (foreground=$fg)"
                }
                elseif ($script:PlayerAttempts -eq 45 -and -not $script:PlayerFallback) {
                    # La ventana propia no ha aparecido: abrimos en el navegador
                    # normal para que al menos la pestana quede abierta.
                    $script:PlayerFallback = $true
                    Write-Log 'Sin ventana propia; abriendo en el navegador por defecto'
                    try { Start-Process $script:PlayerUrl } catch { Write-Log "Fallback error: $_" }
                }
                elseif ($script:PlayerAttempts -ge 60) {
                    $script:PlayerTimer.Stop()
                    Write-Log 'No se encontro la ventana del reproductor'
                    Show-Balloon 'F1 Tray Monitor' 'El reproductor se ha abierto en una pestaña nueva del navegador.' 'Info'
                }
            })
        }
        $script:PlayerTimer.Start()
    } catch {
        Write-Log "Error abriendo reproductor: $_"
        try { Start-Process $Src } catch { Write-Log "Error abriendo URL directa: $_" }
    }
}

# --- Icono F1 -------------------------------------------------------------
function New-F1Icon {
    $icoFile = Join-Path $scriptDir 'f1.ico'
    if (Test-Path $icoFile) {
        try {
            $icon = New-Object System.Drawing.Icon($icoFile)
            return $icon
        } catch { Write-Log "No se pudo cargar f1.ico: $_" }
    }

    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.Clear([System.Drawing.Color]::FromArgb(18, 18, 22))
    $red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225, 6, 0))
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $cell = 8
    for ($y = 0; $y -lt 4; $y++) {
        for ($x = 0; $x -lt 4; $x++) {
            $brush = if ((($x + $y) % 2) -eq 0) { $white } else { $red }
            $g.FillRectangle($brush, ($x * $cell), ($y * $cell), $cell, $cell)
        }
    }
    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    return $icon
}

# --- Estado global --------------------------------------------------------
$script:Posts      = @()
$script:KnownIds   = New-Object 'System.Collections.Generic.HashSet[string]'
$script:FirstSeed  = $false
$script:IsScraping = $false
$script:ScrapeStarted = $null
$script:ScrapeProc = $null
$script:ScrapeTimer = $null
$script:ScrapeOutFile = ''
$script:ScrapeErrFile = ''
$script:MainForm   = $null
$script:ListFlow   = $null
$script:StatusLbl  = $null
$script:RefreshBtn = $null
$script:CountLbl   = $null
$script:Tray       = $null
$script:Menu       = $null
$script:TrayMenu   = $null
$script:TrayMenuList = $null
$script:TrayMenuBox  = $null
$script:TrayRebuild  = $null
$script:TraySearchTimer = $null
$script:SettingsForm = $null
$script:SettingsNeonBtn = $null
$script:SettingsIntervalLbl = $null
$script:SettingsSourcesBox = $null
$script:SettingsSourcesBtn = $null
$script:SettingsSourcesStatus = $null
$script:SettingsTiles = $null
$script:SourcesManual = $false
$script:MainTimer  = $null
$script:NeonTimer  = $null
$script:SavedSearch = ''
$script:AppIcon    = $null
$script:Tip        = $null
$script:BrowserExe = $null
$script:PlayerTimer    = $null
$script:PlayerMarker   = ''
$script:PlayerAttempts = 0
$script:PlayerBefore   = @()
$script:PlayerUrl      = ''
$script:PlayerFallback = $false
$script:Cards      = New-Object System.Collections.ArrayList
$script:CardById   = @{}
$script:CardCache  = @{}
$script:CardCacheCatalog = ''
$script:ListBuildCount = 0
$script:ExpandedId = ''
$script:ListSignature = ''
$script:PostsHash = ''
$script:PostsHashFor = $null
$script:HeaderActions = $null
$script:PlayerEmbedded = $false
$script:SplitRatio  = 0.40
$script:SplitDrag   = $false
$script:SplitTarget = 0
$script:LayoutTimer = $null
$script:StateSaveTimer = $null
$script:WindowPrewarm = $false
$script:PrewarmTimer = $null
$script:HasBuiltOnce = $false
$script:SearchBox  = $null
$script:SearchWrap = $null
$script:SearchTimer = $null
$script:SearchQuery = ''
$script:SearchIndex = @{}
$script:Favorites    = @()
$script:FavoritesOnly = $false
$script:SearchHistory = @()
$script:FavFilterBtn = $null
$script:SearchHistoryForm = $null
$script:SearchHistoryTimer = $null
$script:SearchHistoryShowing = $false
$script:SearchHistoryHidePending = $false
$script:NextPageBtn = $null
$script:LoadAllBtn  = $null
$script:LoadAll     = $false
$script:LoadAllPages = 0
$script:LoadAllMax  = 200
$script:LoadAllTimer = $null
$script:LoadAllProgressFile = Join-Path $scriptDir 'f1_loadall_progress.json'
$script:LoadAllBatchFrom = 2
$script:LoadAllBatchTo = 2
$script:LoadAllUiAt = [DateTime]::MinValue
$script:LoadAllWritten = -1
$script:AutoLoadDone = $false
$script:NextPage   = 2
$script:IsPaging   = $false
$script:NoMorePages = $false
$script:PageProc   = $null
$script:PageTimer  = $null
$script:PageOutFile = ''
$script:PageErrFile = ''
$script:PageRequest = 2
$script:SourcesCatalog = $null
$script:SourcesFetchedAt = ''
$script:SourcesProc = $null
$script:SourcesTimer = $null
$script:TrayHintShown = 0
$script:TrayRightClicked = $false
$script:TrayHintForm = $null
$script:TrayHintTimer = $null

# Limpieza de reproductores temporales antiguos
try {
    Get-ChildItem $env:TEMP -Filter 'f1-player-*.html' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch { }

# --- Notificaciones -------------------------------------------------------
function Show-Balloon {
    param([string]$Title, [string]$Text, [string]$Icon = 'Info')
    if (-not $script:Config.notifications) { return }
    try {
        $tipIcon = [System.Windows.Forms.ToolTipIcon]$Icon
        $script:Tray.ShowBalloonTip(7000, $Title, $Text, $tipIcon)
    } catch { }
}

# --- Aviso animado sobre el icono de la bandeja ---------------------------
# Las dos primeras veces (y solo si el usuario no ha usado aun el clic
# derecho) se muestra un globo junto a la bandeja explicando como abrir la
# ventana y como llegar a las opciones.

function Hide-TrayHint {
    if ($script:TrayHintTimer) {
        try { $script:TrayHintTimer.Stop() } catch { }
        $script:TrayHintTimer = $null
    }
    if ($script:TrayHintForm -and -not $script:TrayHintForm.IsDisposed) {
        try { $script:TrayHintForm.Close() } catch { }
    }
    $script:TrayHintForm = $null
}

function Show-TrayHint {
    if (-not $script:Config.trayHint) { return }
    if ($script:TrayRightClicked) { return }
    if ($script:TrayHintShown -ge 2) { return }
    if ($script:TrayHintForm -and -not $script:TrayHintForm.IsDisposed) { return }

    $accent = Get-NeonColor
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $w = 330
    $h = 68
    $targetX = $wa.Right - $w - 16
    $targetY = $wa.Bottom - $h - 12

    $f = New-Object F1.HintForm
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.BackColor = $accent
    $f.Padding = New-Object System.Windows.Forms.Padding(1)
    $f.Size = New-Object System.Drawing.Size($w, $h)
    $f.Location = New-Object System.Drawing.Point($targetX, ($targetY + 14))
    $f.Opacity = 0
    $f.Cursor = [System.Windows.Forms.Cursors]::Hand
    $script:TrayHintForm = $f
    $script:TrayHintTargetY = $targetY

    $shell = New-Object System.Windows.Forms.Panel
    $shell.Dock = 'Fill'
    $shell.BackColor = [System.Drawing.Color]::FromArgb(14, 14, 20)
    [void]$f.Controls.Add($shell)

    $badge = New-Object System.Windows.Forms.Label
    $badge.Text = 'F1'
    $badge.AutoSize = $false
    $badge.TextAlign = 'MiddleCenter'
    $badge.Font = New-Object System.Drawing.Font('Bahnschrift', 15, ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic))
    $badge.ForeColor = [System.Drawing.Color]::White
    $badge.BackColor = $accent
    $badge.Location = New-Object System.Drawing.Point(12, 12)
    $badge.Size = New-Object System.Drawing.Size(42, 42)
    [void]$shell.Controls.Add($badge)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'El monitor sigue en la bandeja'
    $title.AutoSize = $false
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(244, 244, 250)
    $title.BackColor = [System.Drawing.Color]::Transparent
    $title.Location = New-Object System.Drawing.Point(64, 11)
    $title.Size = New-Object System.Drawing.Size(250, 20)
    [void]$shell.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "Clic: abrir   ·   Clic derecho: opciones`
nEste aviso no volverá a aparecer."
    $sub.AutoSize = $false
    $sub.Font = New-Object System.Drawing.Font('Segoe UI', 7.6)
    $sub.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 176)
    $sub.BackColor = [System.Drawing.Color]::Transparent
    $sub.Location = New-Object System.Drawing.Point(64, 31)
    $sub.Size = New-Object System.Drawing.Size(252, 32)
    [void]$shell.Controls.Add($sub)

    $click = {
        Hide-TrayHint
        Show-MainWindow
    }
    $f.Add_Click($click)
    $shell.Add_Click($click)
    $badge.Add_Click($click)
    $title.Add_Click($click)
    $sub.Add_Click($click)

    $script:TrayHintShown++
    Save-State
    Write-Log "Aviso de bandeja mostrado ($($script:TrayHintShown)/2)"

    $f.Show()

    # Animacion: fundido de entrada + deslizamiento, pausa y fundido de salida.
    $script:TrayHintStep = 0
    if (-not $script:TrayHintTimer) {
        $script:TrayHintTimer = New-Object System.Windows.Forms.Timer
        $script:TrayHintTimer.Interval = 24
        $script:TrayHintTimer.Add_Tick({
            $hf = $script:TrayHintForm
            if (-not $hf -or $hf.IsDisposed) {
                if ($script:TrayHintTimer) { $script:TrayHintTimer.Stop() }
                return
            }
            $script:TrayHintStep++
            $step = [int]$script:TrayHintStep
            if ($step -le 14) {
                $hf.Opacity = [Math]::Min(0.98, $step * 0.07)
                $hf.Top = [Math]::Max([int]$script:TrayHintTargetY, $hf.Top - 1)
            }
            elseif ($step -le 300) {
                $hf.Opacity = 0.98
            }
            else {
                $hf.Opacity = [Math]::Max(0, 0.98 - (($step - 300) * 0.06))
                if ($hf.Opacity -le 0.02) { Hide-TrayHint }
            }
        })
    }
    $script:TrayHintTimer.Start()
}

# --- Menu contextual propio (panel de bandeja) ----------------------------
# No usamos ContextMenuStrip: el menu es un formulario sin bordes con el mismo
# lenguaje visual que la app, buscador integrado y filas desplegables.

function Get-NeonColor {
    $team = [string]$script:Config.neonTeam
    switch ($team) {
        'ferrari'  { return [System.Drawing.Color]::FromArgb(225, 6, 0) }
        'mclaren'  { return [System.Drawing.Color]::FromArgb(255, 135, 0) }
        'mercedes' { return [System.Drawing.Color]::FromArgb(0, 210, 190) }
        'redbull'  { return [System.Drawing.Color]::FromArgb(40, 75, 255) }
        'williams' { return [System.Drawing.Color]::FromArgb(0, 160, 255) }
        'alpine'   { return [System.Drawing.Color]::FromArgb(255, 80, 180) }
        'aston'    { return [System.Drawing.Color]::FromArgb(0, 160, 120) }
        'haas'     { return [System.Drawing.Color]::FromArgb(225, 225, 230) }
        'sauber'   { return [System.Drawing.Color]::FromArgb(82, 226, 82) }
        'lotus'    { return [System.Drawing.Color]::FromArgb(255, 180, 0) }
        'brawn'    { return [System.Drawing.Color]::FromArgb(120, 255, 180) }
        'renault'  { return [System.Drawing.Color]::FromArgb(255, 215, 0) }
        default    { return [System.Drawing.Color]::FromArgb(225, 6, 0) }
    }
}

function Apply-Neon {
    if (-not $script:WebViewCore -or -not $script:WebViewReady) { return }
    try {
        $team = [string]$script:Config.neonTeam
        [void]$script:WebViewCore.ExecuteScriptAsync("window.F1Player && window.F1Player.setNeon('$team');")
    }
    catch { }
}

# --- Capa de la ventana ---------------------------------------------------
function Notify-WebViewLayer {
    if (-not $script:WebViewCore -or -not $script:WebViewReady) { return }
    try {
        [void]$script:WebViewCore.ExecuteScriptAsync("window.F1Player && window.F1Player.setLayer('$($script:WindowLayer)');")
    }
    catch { }
}

function Set-WindowLayer {
    param([string]$Mode)

    $modeKey = ([string]$Mode).ToLowerInvariant()
    if ($modeKey -notin @('normal', 'top', 'bottom')) { $modeKey = 'normal' }
    if (-not $script:MainForm -or $script:MainForm.IsDisposed) { return }

    try {
        $h = $script:MainForm.Handle
        $flagsMove = [uint32]([F1.Native]::SWP_NOMOVE -bor [F1.Native]::SWP_NOSIZE)
        $flagsQuiet = [uint32]([F1.Native]::SWP_NOMOVE -bor [F1.Native]::SWP_NOSIZE -bor [F1.Native]::SWP_NOACTIVATE)

        switch ($modeKey) {
            'top' {
                $script:MainForm.TopMost = $true
                [void][F1.Native]::SetWindowPos($h, [F1.Native]::HWND_TOPMOST, 0, 0, 0, 0, $flagsMove)
            }
            'bottom' {
                $script:MainForm.TopMost = $false
                [void][F1.Native]::SetWindowPos($h, [F1.Native]::HWND_BOTTOM, 0, 0, 0, 0, $flagsQuiet)
            }
            default {
                $script:MainForm.TopMost = $false
                [void][F1.Native]::SetWindowPos($h, [F1.Native]::HWND_NOTOPMOST, 0, 0, 0, 0, $flagsQuiet)
            }
        }

        $script:WindowLayer = $modeKey
        Notify-WebViewLayer
        Write-Log "Capa de ventana: $modeKey"
    }
    catch { Write-Log "No se pudo cambiar la capa de la ventana: $_" }
}

function Cycle-WindowLayer {
    switch ($script:WindowLayer) {
        'normal' { Set-WindowLayer -Mode 'top' }
        'top'    { Set-WindowLayer -Mode 'bottom' }
        default  { Set-WindowLayer -Mode 'normal' }
    }
}

function Update-NeonTimer {
    if (-not $script:NeonTimer) { return }
    if ($script:Config.neonCycle) { $script:NeonTimer.Start() }
    else { $script:NeonTimer.Stop() }
}

function Step-Neon {
    $keys = @($script:NeonTeams | ForEach-Object { $_.key })
    $i = [Array]::IndexOf($keys, [string]$script:Config.neonTeam)
    if ($i -lt 0) { $i = 0 }
    $script:Config.neonTeam = $keys[($i + 1) % $keys.Count]
    Apply-Neon
    Apply-NeonToWindow
    if ($script:SettingsNeonBtn) {
        try {
            $script:SettingsNeonBtn.Text = "$([char]::ConvertFromUtf32(0x25CF))  $($script:NeonTeams[($i + 1) % $keys.Count].name)"
            $script:SettingsNeonBtn.ForeColor = Get-NeonColor
            if ($script:SettingsForm -and -not $script:SettingsForm.IsDisposed) { $script:SettingsForm.BackColor = Get-NeonColor }
        } catch { }
    }
}

# Tine los acentos de la ventana principal con el neon activo: barra de marca,
# boton Actualizar, borde de Cargar todo y marco del panel de bandeja.
function Apply-NeonToWindow {
    $accent = Get-NeonColor
    $r = [int]$accent.R
    $g = [int]$accent.G
    $b = [int]$accent.B
    $lum = 0.299 * $r + 0.587 * $g + 0.114 * $b

    if ($script:AccentPanel) { try { $script:AccentPanel.BackColor = $accent } catch { } }

    if ($script:RefreshBtn) {
        try {
            $script:RefreshBtn.BackColor = $accent
            $script:RefreshBtn.ForeColor = if ($lum -gt 150) { [System.Drawing.Color]::FromArgb(14, 14, 18) } else { [System.Drawing.Color]::White }
            $script:RefreshBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
                [Math]::Min(255, $r + 28), [Math]::Min(255, $g + 28), [Math]::Min(255, $b + 28))
            $script:RefreshBtn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(
                [Math]::Max(0, $r - 24), [Math]::Max(0, $g - 24), [Math]::Max(0, $b - 24))
        } catch { }
    }

    if ($script:LoadAllBtn) {
        try {
            $script:LoadAllBtn.FlatAppearance.BorderColor = $accent
            $soft = [System.Drawing.Color]::FromArgb(
                [Math]::Min(255, $r + 40), [Math]::Min(255, $g + 40), [Math]::Min(255, $b + 40))
            $script:LoadAllBtn.ForeColor = $soft
            $script:LoadAllBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
                [int]([Math]::Max(0, $r * 0.22)), [int]([Math]::Max(0, $g * 0.22)), [int]([Math]::Max(0, $b * 0.22)))
        } catch { }
    }

    if ($script:TrayMenu -and -not $script:TrayMenu.IsDisposed) {
        try { $script:TrayMenu.BackColor = $accent } catch { }
    }
    if ($script:SettingsForm -and -not $script:SettingsForm.IsDisposed) {
        try { $script:SettingsForm.BackColor = $accent } catch { }
    }
    if ($script:Tray) {
        try { $script:Tray.Text = "F1 Tray Monitor · $($script:Config.neonTeam)" } catch { }
    }
}

# Fila desplegable: cabecera + botones de fuente.
function Add-TrayOptions {
    param($Row, $Post, [int]$Width)

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.FlowDirection = 'TopDown'
    $panel.WrapContents = $false
    $panel.AutoSize = $false
    $panel.Width = $Width
    $panel.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 6)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 23)
    $panel.Location = New-Object System.Drawing.Point(0, 36)

    $opts = @(Get-PlayOptions $Post)
    $sources = @()
    foreach ($o in $opts) {
        $sources += [PSCustomObject]@{
            name       = [string]$o.name
            url        = [string]$o.player_url
            service    = [string]$o.service
            serviceKey = [string]$o.serviceKey
            color      = [string]$o.color
            quality    = [string]$o.quality
            lang       = [string]$o.lang
            primary    = [bool]$o.primary
            origin     = [string]$o.origin
        }
    }
    if ($opts.Count -eq 0) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = 'Abrir entrada en el navegador'
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(36, 36, 48)
        $b.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 27)
        $b.ForeColor = [System.Drawing.Color]::FromArgb(205, 205, 215)
        $b.TextAlign = 'MiddleLeft'
        $b.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
        $b.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $b.Size = New-Object System.Drawing.Size(($Width - 16), 28)
        $b.Margin = New-Object System.Windows.Forms.Padding(8, 1, 8, 1)
        $b.Cursor = [System.Windows.Forms.Cursors]::Hand
        $b.Tag = [string]$Post.url
        $b.Add_Click({
            if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }
            Start-Process ([string]$this.Tag)
        })
        [void]$panel.Controls.Add($b)
    }
    else {
        foreach ($opt in $opts) {
            $b = New-Object System.Windows.Forms.Button
            $suffix = @()
            if ($opt.quality) { $suffix += [string]$opt.quality }
            if ($opt.lang) { $suffix += [string]$opt.lang }
            $tail = if ($suffix.Count -gt 0) { '  ·  ' + ($suffix -join ' ') } else { '' }
            $b.Text = "$([char]::ConvertFromUtf32(0x25B6))  $($opt.name)$tail"
            $b.FlatStyle = 'Flat'
            $b.FlatAppearance.BorderSize = 0
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(40, 22, 22)
            $b.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 27)
            $b.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 232)
            $b.TextAlign = 'MiddleLeft'
            $b.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
            $b.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
            $b.Size = New-Object System.Drawing.Size(($Width - 16), 28)
            $b.Margin = New-Object System.Windows.Forms.Padding(8, 1, 8, 1)
            $b.Cursor = [System.Windows.Forms.Cursors]::Hand
            $b.Tag = [PSCustomObject]@{
                src = [string]$opt.player_url; title = [string]$Post.title
                name = [string]$opt.name; type = [string]$Post.type; sources = $sources
            }
            $b.Add_Click({
                $t = $this.Tag
                if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }
                Open-Player -Src $t.src -Title $t.title -Option $t.name -Type $t.type -Sources $t.sources
            })
            [void]$panel.Controls.Add($b)
        }
    }

    $panel.Height = 10 + ($opts.Count * 30)
    if ($opts.Count -eq 0) { $panel.Height = 44 }
    return $panel
}

function Add-TrayRow {
    param($List, $Post, [int]$Width)

    $row = New-Object System.Windows.Forms.Panel
    $row.Width = $Width
    $row.Height = 36
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $row.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30)

    $head = New-Object System.Windows.Forms.Button
    $head.Location = New-Object System.Drawing.Point(0, 0)
    $head.Size = New-Object System.Drawing.Size($Width, 36)
    $head.FlatStyle = 'Flat'
    $head.FlatAppearance.BorderSize = 0
    $head.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $head.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(42, 42, 56)
    $head.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $head.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 242)
    $head.TextAlign = 'MiddleLeft'
    $head.Padding = New-Object System.Windows.Forms.Padding(10, 0, 30, 0)
    $head.Font = New-Object System.Drawing.Font('Segoe UI', 8.8)
    $head.AutoEllipsis = $true
    $head.Cursor = [System.Windows.Forms.Cursors]::Hand
    $head.Text = "$(Get-TypeBullet)  $($Post.type)  $([char]::ConvertFromUtf32(0x00B7))  $(Get-ShortTitle $Post.title)"
    $head.Tag = [PSCustomObject]@{ row = $row; post = $Post; panel = $null; open = $false }
    $head.Add_Click({
        $t = $this.Tag
        if (-not $t.panel) {
            $t.panel = Add-TrayOptions -Row $t.row -Post $t.post -Width $t.row.Width
            [void]$t.row.Controls.Add($t.panel)
        }
        $t.open = -not $t.open
        $t.panel.Visible = $t.open
        $t.row.Height = if ($t.open) { 36 + $t.panel.Height } else { 36 }
    })

    $chevron = New-Object System.Windows.Forms.Label
    $chevron.Text = [char]::ConvertFromUtf32(0x25BE)
    $chevron.AutoSize = $false
    $chevron.TextAlign = 'MiddleCenter'
    $chevron.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 138)
    $chevron.BackColor = [System.Drawing.Color]::Transparent
    $chevron.Location = New-Object System.Drawing.Point(($Width - 26), 0)
    $chevron.Size = New-Object System.Drawing.Size(22, 36)
    $chevron.Cursor = [System.Windows.Forms.Cursors]::Hand
    $chevron.Tag = $head
    $chevron.Add_Click({ $this.Tag.PerformClick() })

    [void]$row.Controls.Add($head)
    [void]$row.Controls.Add($chevron)
    [void]$List.Controls.Add($row)
}

# Las barras de desplazamiento de WinForms son claras por defecto y rompen el
# tema oscuro. uxtheme las pinta con "DarkMode_Explorer" en Windows 10/11; si
# el sistema no lo admite, la llamada no hace nada y todo sigue funcionando.
function Enable-DarkScrollbars {
    param($Control)

    if (-not $Control) { return }
    $paint = {
        param($sender, $e)
        try { [void][F1.Ui]::SetWindowTheme($sender.Handle, 'DarkMode_Explorer', $null) } catch { }
    }
    if ($Control.IsHandleCreated) {
        try { [void][F1.Ui]::SetWindowTheme($Control.Handle, 'DarkMode_Explorer', $null) } catch { }
    }
    $Control.Add_HandleCreated($paint)
}

function Show-TrayMenu {
    if ($script:TrayMenu -and -not $script:TrayMenu.IsDisposed) {
        try { $script:TrayMenu.Close() } catch { }
        $script:TrayMenu = $null
    }

    $accent = Get-NeonColor
    $m = New-Object System.Windows.Forms.Form
    $m.FormBorderStyle = 'None'
    $m.ShowInTaskbar = $false
    $m.TopMost = $true
    $m.StartPosition = 'Manual'
    $m.KeyPreview = $true
    $m.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $m.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $m.BackColor = $accent
    $m.Padding = New-Object System.Windows.Forms.Padding(1)
    $m.Size = New-Object System.Drawing.Size(446, 604)
    $script:TrayMenu = $m

    $shell = New-Object System.Windows.Forms.Panel
    $shell.Dock = 'Fill'
    $shell.BackColor = [System.Drawing.Color]::FromArgb(13, 13, 19)
    [void]$m.Controls.Add($shell)

    $list = New-Object System.Windows.Forms.FlowLayoutPanel
    $list.Dock = 'Fill'
    $list.FlowDirection = 'TopDown'
    $list.WrapContents = $false
    $list.AutoScroll = $true
    $list.BackColor = [System.Drawing.Color]::FromArgb(13, 13, 19)
    $list.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
    [void]$shell.Controls.Add($list)
    Enable-DarkScrollbars $list

    # --- Barra inferior de acciones ----------------------------------------
    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'
    $bottom.Height = 48
    $bottom.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$shell.Controls.Add($bottom)

    $actions = New-Object System.Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Fill'
    $actions.FlowDirection = 'LeftToRight'
    $actions.WrapContents = $false
    $actions.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    $actions.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)
    [void]$bottom.Controls.Add($actions)

    $actionDefs = @(
        @{ text = 'Abrir'; width = 58; action = { if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }; Show-MainWindow } },
        @{ text = 'Actualizar'; width = 78; action = { if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }; Start-Scrape } },
        @{ text = $(if ($script:LoadAll) { 'Detener' } else { 'Cargar todo' }); width = 110; action = { if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }; Toggle-LoadAllPages } },
        @{ text = 'Ajustes'; width = 74; action = { if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }; Show-Settings } },
        @{ text = 'Salir'; width = 48; action = {
                if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }
                try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
                [System.Windows.Forms.Application]::Exit()
            } }
    )
    foreach ($def in $actionDefs) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $def.text
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 38, 50)
        $b.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
        $b.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 230)
        $b.Font = New-Object System.Drawing.Font('Segoe UI', 8.4)
        $b.Size = New-Object System.Drawing.Size([int]$def.width, 30)
        $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
        $b.Cursor = [System.Windows.Forms.Cursors]::Hand
        $b.Add_Click($def.action)
        [void]$actions.Controls.Add($b)
    }

    # --- Buscador -----------------------------------------------------------
    $searchWrap = New-Object System.Windows.Forms.Panel
    $searchWrap.Dock = 'Top'
    $searchWrap.Height = 46
    $searchWrap.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$shell.Controls.Add($searchWrap)

    $searchIcon = New-Object System.Windows.Forms.Label
    $searchIcon.Text = [char]::ConvertFromUtf32(0x2315)
    $searchIcon.Dock = 'Left'
    $searchIcon.Width = 34
    $searchIcon.TextAlign = 'MiddleCenter'
    $searchIcon.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $searchIcon.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 155)
    [void]$searchWrap.Controls.Add($searchIcon)

    $box = New-Object System.Windows.Forms.TextBox
    $box.BorderStyle = 'None'
    $box.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 34)
    $box.ForeColor = [System.Drawing.Color]::FromArgb(236, 236, 243)
    $box.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $box.Dock = 'Fill'
    $box.Margin = New-Object System.Windows.Forms.Padding(0)
    $box.Add_HandleCreated({
        try { [void][F1.Ui]::SendMessage($this.Handle, 0x1501, [IntPtr]1, 'Buscar GP, sesión u opción...') } catch { }
    })
    $searchPad = New-Object System.Windows.Forms.Panel
    $searchPad.Dock = 'Fill'
    $searchPad.Padding = New-Object System.Windows.Forms.Padding(0, 8, 8, 8)
    $searchPad.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$searchPad.Controls.Add($box)
    [void]$searchWrap.Controls.Add($searchPad)

    # --- Cabecera -----------------------------------------------------------
    $head = New-Object System.Windows.Forms.Panel
    $head.Dock = 'Top'
    $head.Height = 62
    $head.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$shell.Controls.Add($head)

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = 'Left'
    $bar.Width = 4
    $bar.BackColor = $accent
    [void]$head.Controls.Add($bar)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'F1 TRAY MONITOR'
    $title.AutoSize = $false
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 246)
    $title.Location = New-Object System.Drawing.Point(16, 6)
    $title.Size = New-Object System.Drawing.Size(300, 26)
    [void]$head.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "$($script:Posts.Count) entradas  $([char]::ConvertFromUtf32(0x00B7))  clic en el icono para mostrar u ocultar"
    $sub.AutoSize = $false
    $sub.Font = New-Object System.Drawing.Font('Segoe UI', 7.8)
    $sub.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 155)
    $sub.Location = New-Object System.Drawing.Point(17, 32)
    $sub.Size = New-Object System.Drawing.Size(410, 20)
    [void]$head.Controls.Add($sub)

    # --- Filas --------------------------------------------------------------
    $script:TrayMenuList = $list
    $script:TrayMenuBox = $box
    $script:TrayRebuild = {
        $list = $script:TrayMenuList
        $box = $script:TrayMenuBox
        if (-not $list -or $list.IsDisposed) { return }
        $list.SuspendLayout()
        try {
            while ($list.Controls.Count -gt 0) { $list.Controls[0].Dispose() }
            $q = ConvertTo-SearchText $box.Text
            $items = @(Get-FilteredPosts -Query $q)
            $width = [Math]::Max(220, $list.ClientSize.Width - 38)
            if ($items.Count -eq 0) {
                $lbl = New-Object System.Windows.Forms.Label
                $lbl.Text = 'Sin resultados. Prueba con un circuito, sesión o idioma.'
                $lbl.AutoSize = $false
                $lbl.Size = New-Object System.Drawing.Size($width, 44)
                $lbl.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 165)
                $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 8.8)
                [void]$list.Controls.Add($lbl)
            }
            else {
                $shown = 0
                foreach ($p in $items) {
                    if ($shown -ge 40) { break }
                    Add-TrayRow -List $list -Post $p -Width $width
                    $shown++
                }
            }
        }
        finally { $list.ResumeLayout() }
    }

    $box.Add_TextChanged({
        $script:TraySearchTimer.Stop()
        $script:TraySearchTimer.Start()
    })
    $script:TraySearchTimer = New-Object System.Windows.Forms.Timer
    $script:TraySearchTimer.Interval = 140
    $script:TraySearchTimer.Add_Tick({
        $script:TraySearchTimer.Stop()
        & $script:TrayRebuild
    })

    $clear = New-Object System.Windows.Forms.Label
    $clear.Text = [char]::ConvertFromUtf32(0x2715)
    $clear.Dock = 'Right'
    $clear.Width = 26
    $clear.TextAlign = 'MiddleCenter'
    $clear.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 155)
    $clear.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $clear.Cursor = [System.Windows.Forms.Cursors]::Hand
    $clear.Add_Click({ $script:TrayMenuBox.Clear() })
    [void]$searchWrap.Controls.Add($clear)

    # El relleno debe acoplarse al final para no quedar bajo los iconos.
    [void]$searchWrap.Controls.SetChildIndex($searchPad, 0)
    [void]$searchWrap.Controls.SetChildIndex($searchIcon, 1)
    [void]$searchWrap.Controls.SetChildIndex($clear, 2)

    # Orden de acoplado: el Fill ya esta agregado; ahora cabecera y buscador.
    [void]$shell.Controls.SetChildIndex($list, 0)
    [void]$shell.Controls.SetChildIndex($bottom, 1)
    [void]$shell.Controls.SetChildIndex($searchWrap, 2)
    [void]$shell.Controls.SetChildIndex($head, 3)

    # Si se recuerda la busqueda, precargar el filtro en el panel.
    if ($script:Config.rememberSearch -and $script:SavedSearch) { $box.Text = $script:SavedSearch }

    & $script:TrayRebuild

    $m.Add_Deactivate({ try { $this.Close() } catch { } })
    $m.Add_FormClosed({
        try { $script:TraySearchTimer.Stop() } catch { }
        if ($script:TrayMenu -eq $this) { $script:TrayMenu = $null }
    })
    $m.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $this.Close() }
    })

    $pos = [System.Windows.Forms.Cursor]::Position
    $scr = [System.Windows.Forms.Screen]::FromPoint($pos)
    $x = [Math]::Min($pos.X, $scr.WorkingArea.Right - $m.Width - 8)
    $y = [Math]::Min($pos.Y, $scr.WorkingArea.Bottom - $m.Height - 8)
    $x = [Math]::Max($scr.WorkingArea.Left + 8, $x)
    $y = [Math]::Max($scr.WorkingArea.Top + 8, $y)
    $m.Location = New-Object System.Drawing.Point($x, $y)

    $m.Show()
    $m.Activate()
    try { [void][F1.User32]::SetForegroundWindow($m.Handle) } catch { }
    $box.Focus() | Out-Null
}

function Refresh-Menu {
    # El panel de bandeja se construye al abrirlo: no hay menu persistente.
}

# --- Ajustes por iconos ----------------------------------------------------
# Cada baldosa es un interruptor con globo informativo. Los cambios se aplican
# y se guardan al instante en config.json.

function New-SettingTile {
    param(
        [string]$Key,
        [string]$Icon,
        [string]$Title,
        [string]$Desc,
        [string]$Tip
    )

    $on = [bool]$script:Config[$Key]
    $tile = New-Object System.Windows.Forms.Panel
    $tile.Size = New-Object System.Drawing.Size(278, 84)
    $tile.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $tile.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    $tile.Cursor = [System.Windows.Forms.Cursors]::Hand

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Location = New-Object System.Drawing.Point(0, 0)
    $bar.Size = New-Object System.Drawing.Size(4, 84)
    $bar.BackColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(58, 58, 72) }
    [void]$tile.Controls.Add($bar)

    $iconLbl = New-Object System.Windows.Forms.Label
    $iconLbl.Text = $Icon
    $iconLbl.AutoSize = $false
    $iconLbl.TextAlign = 'MiddleCenter'
    $iconLbl.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 17)
    $iconLbl.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 245)
    $iconLbl.Location = New-Object System.Drawing.Point(12, 18)
    $iconLbl.Size = New-Object System.Drawing.Size(42, 42)
    $iconLbl.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 40)
    [void]$tile.Controls.Add($iconLbl)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.AutoSize = $false
    $titleLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8.4, [System.Drawing.FontStyle]::Bold)
    $titleLbl.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 246)
    $titleLbl.Location = New-Object System.Drawing.Point(62, 13)
    $titleLbl.Size = New-Object System.Drawing.Size(172, 20)
    [void]$tile.Controls.Add($titleLbl)

    $descLbl = New-Object System.Windows.Forms.Label
    $descLbl.Text = $Desc
    $descLbl.AutoSize = $false
    $descLbl.Font = New-Object System.Drawing.Font('Segoe UI', 7.6)
    $descLbl.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 165)
    $descLbl.Location = New-Object System.Drawing.Point(62, 33)
    $descLbl.Size = New-Object System.Drawing.Size(200, 42)
    [void]$tile.Controls.Add($descLbl)

    $stateLbl = New-Object System.Windows.Forms.Label
    $stateLbl.Text = if ($on) { 'ON' } else { 'OFF' }
    $stateLbl.AutoSize = $false
    $stateLbl.TextAlign = 'MiddleRight'
    $stateLbl.Font = New-Object System.Drawing.Font('Segoe UI', 7.2, [System.Drawing.FontStyle]::Bold)
    $stateLbl.ForeColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(120, 120, 138) }
    $stateLbl.Location = New-Object System.Drawing.Point(236, 13)
    $stateLbl.Size = New-Object System.Drawing.Size(32, 18)
    [void]$tile.Controls.Add($stateLbl)

    $tag = [PSCustomObject]@{ key = $Key; state = $stateLbl; bar = $bar; tile = $tile }
    if (-not $script:SettingsTiles) { $script:SettingsTiles = New-Object System.Collections.ArrayList }
    [void]$script:SettingsTiles.Add($tag)
    $handler = {
        $t = $this.Tag
        $script:Config[$t.key] = -not [bool]$script:Config[$t.key]
        $on = [bool]$script:Config[$t.key]
        Save-Config
        $t.state.Text = if ($on) { 'ON' } else { 'OFF' }
        $t.state.ForeColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(120, 120, 138) }
        $t.bar.BackColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(58, 58, 72) }
        switch ($t.key) {
            'neonCycle'      { Update-NeonTimer }
            'rememberSearch' {
                if (-not $on) { $script:SavedSearch = ''; Save-State }
            }
            'sourcesEnabled' {
                Update-SourcesStatusLabel
                if ($on) {
                    if (-not $script:SourcesCatalog) { Read-SourcesCatalog }
                    Start-SourcesDownload
                    Refresh-SourceOptions
                }
                else { Refresh-SourceOptions }
            }
        }
    }

    foreach ($c in @($tile, $bar, $iconLbl, $titleLbl, $descLbl, $stateLbl)) {
        $c.Tag = $tag
        $c.Add_Click($handler)
        $c.Add_MouseEnter({ $this.Tag.tile.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 40) })
        $c.Add_MouseLeave({ $this.Tag.tile.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30) })
    }
    if ($script:Tip) {
        foreach ($c in @($tile, $iconLbl, $titleLbl, $descLbl, $stateLbl)) { $script:Tip.SetToolTip($c, $Tip) }
    }
    return $tile
}

# Refresca el estado visual de todas las baldosas (por si un cambio se hace
# desde otro sitio, como el boton de actualizar el catalogo).
function Sync-SettingsTiles {
    foreach ($t in @($script:SettingsTiles)) {
        if (-not $t -or -not $t.tile -or $t.tile.IsDisposed) { continue }
        $on = [bool]$script:Config[$t.key]
        $t.state.Text = if ($on) { 'ON' } else { 'OFF' }
        $t.state.ForeColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(120, 120, 138) }
        $t.bar.BackColor = if ($on) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(58, 58, 72) }
    }
}

# Estado legible del catalogo bajo el campo de URL.
function Update-SourcesStatusLabel {
    param([string]$Text)

    $lbl = $script:SettingsSourcesStatus
    if (-not $lbl -or $lbl.IsDisposed) { return }

    if ($Text) {
        $lbl.Text = $Text
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 198)
        return
    }

    if ($script:SourcesProc) {
        $lbl.Text = 'Descargando catálogo...'
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 198)
        return
    }

    $rules = 0
    $svc = 0
    $ver = ''
    if ($script:SourcesCatalog) {
        $rules = @($script:SourcesCatalog.rules).Count
        if ($script:SourcesCatalog.services) { $svc = @($script:SourcesCatalog.services.PSObject.Properties).Count }
        $ver = [string]$script:SourcesCatalog.version
    }
    $when = ''
    if ($script:SourcesFetchedAt) {
        try { $when = ([datetime]$script:SourcesFetchedAt).ToLocalTime().ToString('dd/MM HH:mm') } catch { }
    }
    if ($script:Config.sourcesEnabled) {
        $lbl.Text = "Activo · $rules reglas · $svc servicios · versión $ver" + $(if ($when) { " · $when" } else { ' · copia local' })
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(130, 170, 150)
    }
    else {
        $lbl.Text = 'Desactivado. Activa «Catálogo de fuentes» para usar estas opciones.'
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(160, 140, 120)
    }
}

# --- Mantenimiento: version, registro y copias de ajustes -----------------
# Compara dos versiones tipo 1.3.0 o v1.3.0-beta. Devuelve 1, 0 o -1.
function Compare-AppVersion {
    param([string]$Left, [string]$Right)

    $parse = {
        param([string]$v)
        $clean = ([string]$v).Trim() -replace '^[vV]', ''
        $clean = ($clean -split '-')[0]
        return @(($clean -split '\.') | ForEach-Object {
                $n = 0
                if ([int]::TryParse($_, [ref]$n)) { $n } else { 0 }
            })
    }
    $a = & $parse $Left
    $b = & $parse $Right
    $len = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $len; $i++) {
        $x = if ($i -lt $a.Count) { [int]$a[$i] } else { 0 }
        $y = if ($i -lt $b.Count) { [int]$b[$i] } else { 0 }
        if ($x -gt $y) { return 1 }
        if ($x -lt $y) { return -1 }
    }
    return 0
}

function Set-MaintenanceStatus {
    param([string]$Text, [bool]$Error = $false)

    if (-not $script:SettingsMaintStatus -or $script:SettingsMaintStatus.IsDisposed) { return }
    $script:SettingsMaintStatus.Text = $Text
    $script:SettingsMaintStatus.ForeColor = if ($Error) {
        [System.Drawing.Color]::FromArgb(236, 118, 108)
    }
    else {
        [System.Drawing.Color]::FromArgb(138, 138, 154)
    }
}

function Update-SettingsUpdateUI {
    if (-not $script:SettingsForm -or $script:SettingsForm.IsDisposed) { return }

    if ($script:SettingsUpdateStatus -and -not $script:SettingsUpdateStatus.IsDisposed) {
        if ($script:UpdateBusy) {
            $script:SettingsUpdateStatus.Text = 'Buscando la última versión...'
            $script:SettingsUpdateStatus.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 168)
        }
        elseif ($script:UpdateLatest) {
            if ((Compare-AppVersion $script:UpdateLatest $script:AppVersion) -gt 0) {
                $script:SettingsUpdateStatus.Text = "Nueva versión $($script:UpdateLatest) disponible"
                $script:SettingsUpdateStatus.ForeColor = Get-NeonColor
            }
            else {
                $script:SettingsUpdateStatus.Text = "Estás al día (v$($script:AppVersion))"
                $script:SettingsUpdateStatus.ForeColor = [System.Drawing.Color]::FromArgb(138, 138, 154)
            }
        }
        else {
            $script:SettingsUpdateStatus.Text = if ($script:UpdateStatusText) { $script:UpdateStatusText } else { 'Sin comprobar todavía.' }
            $script:SettingsUpdateStatus.ForeColor = [System.Drawing.Color]::FromArgb(138, 138, 154)
        }
    }

    if ($script:SettingsUpdateLink -and -not $script:SettingsUpdateLink.IsDisposed) {
        $show = $script:UpdateUrl -and $script:UpdateLatest -and ((Compare-AppVersion $script:UpdateLatest $script:AppVersion) -gt 0)
        $script:SettingsUpdateLink.Visible = [bool]$show
    }
}

function Show-LogViewer {
    if ($script:LogForm -and -not $script:LogForm.IsDisposed) {
        $script:LogForm.Activate()
        return
    }

    $accent = Get-NeonColor
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Registro'
    $f.FormBorderStyle = 'None'
    $f.ShowInTaskbar = $false
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $f.BackColor = $accent
    $f.Padding = New-Object System.Windows.Forms.Padding(1)
    $f.Size = New-Object System.Drawing.Size(760, 560)
    $script:LogForm = $f

    $shell = New-Object System.Windows.Forms.Panel
    $shell.Dock = 'Fill'
    $shell.BackColor = [System.Drawing.Color]::FromArgb(13, 13, 19)
    [void]$f.Controls.Add($shell)

    $head = New-Object System.Windows.Forms.Panel
    $head.Dock = 'Top'
    $head.Height = 58
    $head.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$shell.Controls.Add($head)

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = 'Left'
    $bar.Width = 4
    $bar.BackColor = $accent
    [void]$head.Controls.Add($bar)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'REGISTRO'
    $title.AutoSize = $false
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 246)
    $title.Location = New-Object System.Drawing.Point(18, 6)
    $title.Size = New-Object System.Drawing.Size(300, 28)
    [void]$head.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = 'Últimas 800 líneas de monitor.log. Se renueva al abrir este panel.'
    $sub.AutoSize = $false
    $sub.Font = New-Object System.Drawing.Font('Segoe UI', 7.8)
    $sub.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 155)
    $sub.Location = New-Object System.Drawing.Point(19, 34)
    $sub.Size = New-Object System.Drawing.Size(560, 18)
    [void]$head.Controls.Add($sub)

    $headClose = New-Object System.Windows.Forms.Button
    $headClose.Text = [char]::ConvertFromUtf32(0x2715)
    $headClose.FlatStyle = 'Flat'
    $headClose.FlatAppearance.BorderSize = 0
    $headClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(196, 43, 28)
    $headClose.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    $headClose.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 232)
    $headClose.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $headClose.Size = New-Object System.Drawing.Size(38, 30)
    $headClose.Location = New-Object System.Drawing.Point(706, 10)
    $headClose.Anchor = 'Top,Right'
    $headClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $headClose.Add_Click({ $script:LogForm.Close() })
    [void]$head.Controls.Add($headClose)

    $wrap = New-Object System.Windows.Forms.Panel
    $wrap.Dock = 'Fill'
    $wrap.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)
    $wrap.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
    [void]$shell.Controls.Add($wrap)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Dock = 'Fill'
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.WordWrap = $false
    $box.ScrollBars = 'Both'
    $box.BorderStyle = 'None'
    $box.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)
    $box.ForeColor = [System.Drawing.Color]::FromArgb(196, 202, 214)
    $box.Font = New-Object System.Drawing.Font('Consolas', 8.4)
    [void]$wrap.Controls.Add($box)
    Enable-DarkScrollbars $box

    $foot = New-Object System.Windows.Forms.Panel
    $foot.Dock = 'Bottom'
    $foot.Height = 52
    $foot.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$shell.Controls.Add($foot)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = ''
    $status.AutoSize = $false
    $status.TextAlign = 'MiddleLeft'
    $status.Font = New-Object System.Drawing.Font('Segoe UI', 7.6)
    $status.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 146)
    $status.Location = New-Object System.Drawing.Point(18, 0)
    $status.Size = New-Object System.Drawing.Size(384, 52)
    [void]$foot.Controls.Add($status)

    $readLog = {
        try {
            if (-not (Test-Path $logFile)) {
                $box.Text = 'Todavía no hay registro. Arranca el monitor para generarlo.'
                $status.Text = 'monitor.log  ·  vacío'
                return
            }
            $fs = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
            $text = $sr.ReadToEnd()
            $sr.Dispose()
            $fs.Dispose()
            $lines = @($text -split "`r?`n")
            if ($lines.Count -gt 800) { $text = (@($lines[($lines.Count - 800)..($lines.Count - 1)]) -join "`r`n") }
            $box.Text = $text
            $box.SelectionStart = $box.TextLength
            $box.ScrollToCaret()
            $status.Text = "$([Math]::Min(800, $lines.Count)) líneas  ·  monitor.log  ·  $([Math]::Round((Get-Item $logFile).Length / 1KB, 1)) KB"
        }
        catch {
            $box.Text = "No se pudo leer el registro: $($_.Exception.Message)"
            $status.Text = 'Error de lectura'
        }
    }

    $reload = New-Object System.Windows.Forms.Button
    $reload.Text = 'Recargar'
    $reload.FlatStyle = 'Flat'
    $reload.FlatAppearance.BorderSize = 1
    $reload.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $reload.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $reload.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $reload.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $reload.Font = New-Object System.Drawing.Font('Segoe UI', 8.4, [System.Drawing.FontStyle]::Bold)
    $reload.Size = New-Object System.Drawing.Size(96, 30)
    $reload.Location = New-Object System.Drawing.Point(444, 11)
    $reload.Anchor = 'Top,Right'
    $reload.Cursor = [System.Windows.Forms.Cursors]::Hand
    $reload.Add_Click({ & $readLog })
    [void]$foot.Controls.Add($reload)

    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = 'Copiar'
    $copy.FlatStyle = 'Flat'
    $copy.FlatAppearance.BorderSize = 1
    $copy.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $copy.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $copy.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $copy.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $copy.Font = New-Object System.Drawing.Font('Segoe UI', 8.4)
    $copy.Size = New-Object System.Drawing.Size(90, 30)
    $copy.Location = New-Object System.Drawing.Point(548, 11)
    $copy.Anchor = 'Top,Right'
    $copy.Cursor = [System.Windows.Forms.Cursors]::Hand
    $copy.Add_Click({
        try {
            if ($box.TextLength -gt 0) {
                [System.Windows.Forms.Clipboard]::SetText($box.Text)
                $status.Text = 'Registro copiado al portapapeles'
            }
        } catch { $status.Text = 'No se pudo copiar' }
    })
    [void]$foot.Controls.Add($copy)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Cerrar'
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderSize = 1
    $close.FlatAppearance.BorderColor = $accent
    $close.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $close.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $close.ForeColor = $accent
    $close.Font = New-Object System.Drawing.Font('Segoe UI', 8.4, [System.Drawing.FontStyle]::Bold)
    $close.Size = New-Object System.Drawing.Size(92, 30)
    $close.Location = New-Object System.Drawing.Point(646, 11)
    $close.Anchor = 'Top,Right'
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.Add_Click({ $script:LogForm.Close() })
    [void]$foot.Controls.Add($close)

    $f.Add_FormClosed({ $script:LogForm = $null })
    $f.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $this.Close() }
    })
    $f.KeyPreview = $true

    [void]$shell.Controls.SetChildIndex($wrap, 0)
    [void]$shell.Controls.SetChildIndex($foot, 1)
    [void]$shell.Controls.SetChildIndex($head, 2)

    & $readLog
    $f.Show()
    $f.Activate()
}

# Un unico JSON portable: configuracion, favoritos, busquedas y catalogo.
function Export-Settings {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Exportar ajustes de F1 Tray Monitor'
    $dlg.Filter = 'Ajustes JSON (*.json)|*.json'
    $dlg.FileName = "f1-tray-monitor-ajustes-$(Get-Date -Format 'yyyyMMdd').json"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $sources = $null
        if (Test-Path $sourcesFile) {
            try { $sources = [System.IO.File]::ReadAllText($sourcesFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { }
        }
        $payload = [PSCustomObject]@{
            app           = 'F1 Tray Monitor'
            version       = [string]$script:AppVersion
            exportedAt    = (Get-Date).ToString('o')
            config        = Get-ConfigSnapshot
            favorites     = @($script:Favorites)
            searchHistory = @($script:SearchHistory)
            sources       = $sources
        }
        $json = $payload | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($dlg.FileName, $json, (New-Object System.Text.UTF8Encoding($false)))
        Set-MaintenanceStatus "Ajustes exportados: $(Split-Path $dlg.FileName -Leaf)"
        Write-Log "Ajustes exportados a $($dlg.FileName)"
    }
    catch {
        Set-MaintenanceStatus "No se pudo exportar: $($_.Exception.Message)" -Error $true
        Write-Log "Error exportando ajustes: $_"
    }
}

function Import-Settings {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Importar ajustes de F1 Tray Monitor'
    $dlg.Filter = 'Ajustes JSON (*.json)|*.json|Todos los archivos (*.*)|*.*'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $raw = [System.IO.File]::ReadAllText($dlg.FileName, [System.Text.Encoding]::UTF8)
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data) { throw 'El archivo está vacío.' }

        $cfg = $data.config
        if ($cfg) {
            if ($null -ne $cfg.intervalMinutes) { $script:Config.intervalMinutes = [Math]::Max(1, [Math]::Min(180, [int]$cfg.intervalMinutes)) }
            if ($null -ne $cfg.days) {
                $days = @($cfg.days | ForEach-Object { [string]$_ } | Where-Object { $_ })
                if ($days.Count -gt 0) { $script:Config.days = $days }
            }
            if ($cfg.playerMode) {
                $mode = ([string]$cfg.playerMode).ToLowerInvariant()
                if ($mode -in @('embedded', 'external')) { $script:Config.playerMode = $mode }
            }
            if ($cfg.playerBrowser) { $script:Config.playerBrowser = [string]$cfg.playerBrowser }
            foreach ($k in @('cleanPlayer', 'notifications', 'startMinimized', 'openVideoOnly', 'autoLoadAll',
                    'rememberSearch', 'neonCycle', 'sourcesEnabled', 'trayHint', 'updateCheck')) {
                if ($null -ne $cfg.$k) { $script:Config[$k] = [bool]$cfg.$k }
            }
            if ($null -ne $cfg.maxPostsOnFirstRun) { $script:Config.maxPostsOnFirstRun = [Math]::Max(1, [int]$cfg.maxPostsOnFirstRun) }
            if ($cfg.neonTeam) {
                $team = ([string]$cfg.neonTeam).ToLowerInvariant()
                if ($script:NeonTeams | Where-Object { $_.key -eq $team }) { $script:Config.neonTeam = $team }
            }
            if ($cfg.sourcesUrl) { $script:Config.sourcesUrl = [string]$cfg.sourcesUrl }
            if ($null -ne $cfg.sourcesRefreshHours) { $script:Config.sourcesRefreshHours = [Math]::Max(1, [Math]::Min(168, [int]$cfg.sourcesRefreshHours)) }
        }

        if ($null -ne $data.favorites) {
            $script:Favorites = @($data.favorites | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Unique)
        }
        if ($null -ne $data.searchHistory) {
            $script:SearchHistory = @($data.searchHistory | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -First 8)
        }

        if ($data.sources -and ($data.sources.services -or $data.sources.rules)) {
            $srcJson = $data.sources | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($sourcesFile, $srcJson, (New-Object System.Text.UTF8Encoding($false)))
            [void](Read-SourcesCatalog)
            Refresh-SourceOptions
        }

        Save-Config
        Save-State
        if ($script:MainTimer) { $script:MainTimer.Interval = [Math]::Max(1, [int]$script:Config.intervalMinutes) * 60 * 1000 }
        if ($script:SettingsIntervalLbl -and -not $script:SettingsIntervalLbl.IsDisposed) {
            $script:SettingsIntervalLbl.Text = "$([int]$script:Config.intervalMinutes) min"
        }
        [void](Sync-SettingsTiles)
        Apply-Neon
        Apply-NeonToWindow
        Update-FavoriteFilterButton
        Build-List
        Update-FavoriteStars
        Set-MaintenanceStatus "Ajustes importados: $(Split-Path $dlg.FileName -Leaf)"
        Write-Log "Ajustes importados desde $($dlg.FileName)"
    }
    catch {
        Set-MaintenanceStatus "No se pudo importar: $($_.Exception.Message)" -Error $true
        Write-Log "Error importando ajustes: $_"
    }
}

# --- Comprobacion de actualizaciones (GitHub Releases) --------------------
# Descarga asincrona con WebClient + Timer: la interfaz nunca se bloquea y
# cualquier fallo (sin red, 404, API limitada) se resuelve en silencio.
function Complete-UpdateCheck {
    if (-not $script:UpdateTask) { return }
    if (-not $script:UpdateTask.IsCompleted) { return }

    if ($script:UpdateTimer) {
        try { $script:UpdateTimer.Stop() } catch { }
    }
    $task = $script:UpdateTask
    $script:UpdateTask = $null
    $script:UpdateBusy = $false
    $script:UpdateCheckedAt = (Get-Date).ToString('o')

    try {
        if ($task.IsFaulted) { throw $task.Exception.GetBaseException() }
        if ($task.IsCanceled) { throw 'consulta cancelada' }
        $rel = $task.Result | ConvertFrom-Json
        $tag = ([string]$rel.tag_name) -replace '^[vV]', ''
        if (-not $tag) { throw 'respuesta sin version' }
        $script:UpdateLatest = $tag
        $script:UpdateUrl = [string]$rel.html_url
        $script:UpdateStatusText = "Última versión publicada: $tag"
        if ((Compare-AppVersion $tag $script:AppVersion) -gt 0) {
            Write-Log "Actualizaciones: nueva version disponible $tag"
        }
        else {
            Write-Log "Actualizaciones: al dia (v$($script:AppVersion))"
        }
    }
    catch {
        $script:UpdateStatusText = 'No se pudo comprobar la versión'
        Write-Log "Actualizaciones: comprobacion fallida ($($_.Exception.Message))"
    }
    finally {
        if ($script:UpdateClient) {
            try { $script:UpdateClient.Dispose() } catch { }
            $script:UpdateClient = $null
        }
        Save-State
        Update-SettingsUpdateUI
    }
}

function Start-UpdateCheck {
    param([bool]$Manual = $false)

    if ($script:UpdateBusy) {
        if ($Manual) { Set-MaintenanceStatus 'Ya hay una comprobación en curso.' }
        return
    }
    if (-not $Manual -and -not $script:Config.updateCheck) { return }

    $script:UpdateBusy = $true
    $script:UpdateStatusText = 'Comprobando la última versión...'
    Update-SettingsUpdateUI
    if ($Manual) { Set-MaintenanceStatus 'Comprobando versiones en GitHub...' }

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', "F1-Tray-Monitor/$($script:AppVersion)")
        $wc.Headers.Add('Accept', 'application/vnd.github+json')
        $script:UpdateClient = $wc
        $script:UpdateTask = $wc.DownloadStringTaskAsync("https://api.github.com/repos/$($script:AppRepo)/releases/latest")
    }
    catch {
        $script:UpdateBusy = $false
        $script:UpdateStatusText = 'No se pudo comprobar la versión'
        Write-Log "Actualizaciones: $($_.Exception.Message)"
        Update-SettingsUpdateUI
        return
    }

    if (-not $script:UpdateTimer) {
        $script:UpdateTimer = New-Object System.Windows.Forms.Timer
        $script:UpdateTimer.Interval = 300
        $script:UpdateTimer.Add_Tick({ Complete-UpdateCheck })
    }
    $script:UpdateTimer.Start()
}

# Al arrancar: una comprobacion silenciosa cada 24 h si el ajuste esta activo.
function Start-UpdateAutoCheck {
    if (-not $script:Config.updateCheck) { return }
    if ($script:UpdateCheckedAt) {
        try {
            if (((Get-Date) - [datetime]::Parse($script:UpdateCheckedAt)).TotalHours -lt 24) { return }
        } catch { }
    }
    Start-UpdateCheck
}

function Show-Settings {
    if ($script:SettingsForm -and -not $script:SettingsForm.IsDisposed) {
        $script:SettingsForm.Activate()
        return
    }
    $script:SettingsTiles = New-Object System.Collections.ArrayList

    $accent = Get-NeonColor
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.ShowInTaskbar = $false
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $f.BackColor = $accent
    $f.Padding = New-Object System.Windows.Forms.Padding(1)
    # Alto pensado para las nueve baldosas, la fila del catálogo y el
    # mantenimiento sin scroll. En pantallas bajas se limita y el panel se desplaza.
    $settingsH = 950
    try {
        $waSettings = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $settingsH = [Math]::Min($settingsH, [Math]::Max(560, $waSettings.Height - 40))
    }
    catch { }
    # En la autoprueba se captura el panel entero aunque la pantalla sea baja:
    # PrintWindow pinta la ventana completa y la documentacion sale sin cortes.
    if ($SelfTest) { $settingsH = 950 }
    $f.Size = New-Object System.Drawing.Size(628, $settingsH)
    $script:SettingsForm = $f

    $shell = New-Object System.Windows.Forms.Panel
    $shell.Dock = 'Fill'
    $shell.BackColor = [System.Drawing.Color]::FromArgb(13, 13, 19)
    [void]$f.Controls.Add($shell)

    # --- Cabecera ----------------------------------------------------------
    $head = New-Object System.Windows.Forms.Panel
    $head.Dock = 'Top'
    $head.Height = 70
    $head.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$shell.Controls.Add($head)

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = 'Left'
    $bar.Width = 4
    $bar.BackColor = $accent
    [void]$head.Controls.Add($bar)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'AJUSTES'
    $title.AutoSize = $false
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 246)
    $title.Location = New-Object System.Drawing.Point(18, 6)
    $title.Size = New-Object System.Drawing.Size(300, 30)
    [void]$head.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = 'Pasa el ratón por cada icono. Los cambios se guardan al instante.'
    $sub.AutoSize = $false
    $sub.Font = New-Object System.Drawing.Font('Segoe UI', 7.9)
    $sub.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 155)
    $sub.Location = New-Object System.Drawing.Point(19, 38)
    $sub.Size = New-Object System.Drawing.Size(540, 20)
    [void]$head.Controls.Add($sub)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = [char]::ConvertFromUtf32(0x2715)
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderSize = 0
    $close.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(196, 43, 28)
    $close.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    $close.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 232)
    $close.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $close.Size = New-Object System.Drawing.Size(38, 30)
    $close.Location = New-Object System.Drawing.Point(574, 12)
    $close.Anchor = 'Top,Right'
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.Add_Click({ $script:SettingsForm.Close() })
    [void]$head.Controls.Add($close)

    # --- Baldosas ----------------------------------------------------------
    $content = New-Object System.Windows.Forms.FlowLayoutPanel
    $content.Dock = 'Fill'
    $content.FlowDirection = 'LeftToRight'
    $content.WrapContents = $true
    $content.AutoScroll = $true
    $content.BackColor = [System.Drawing.Color]::FromArgb(13, 13, 19)
    $content.Padding = New-Object System.Windows.Forms.Padding(16, 14, 6, 6)
    [void]$shell.Controls.Add($content)
    Enable-DarkScrollbars $content

    $tiles = @(
        @{ key = 'notifications';  icon = [char]::ConvertFromUtf32(0x25C9); title = 'Notificaciones'; desc = 'Avisos de nuevas entradas y del reproductor.'; tip = "Muestra globos de aviso en la bandeja cuando aparece una entrada nueva o el reproductor se abre en el navegador.`n`nDesactívalo para no recibir interrupciones." },
        @{ key = 'startMinimized'; icon = [char]::ConvertFromUtf32(0x25AC); title = 'Iniciar en bandeja'; desc = 'Arranca oculto; abre la ventana desde el icono.'; tip = "Al iniciar Windows, el monitor se queda en la bandeja sin abrir la ventana.`n`nHaz clic izquierdo en el icono para mostrarla u ocultarla cuando quieras." },
        @{ key = 'openVideoOnly';  icon = [char]::ConvertFromUtf32(0x25B6); title = 'Solo vídeo'; desc = 'Al reproducir, oculta lista y barras.'; tip = "Cuando eliges una fuente, la ventana pasa directamente a modo solo vídeo: el vídeo ocupa todo y la lista desaparece.`n`nPuedes recuperar la lista con el botón de la barra flotante del reproductor." },
        @{ key = 'autoLoadAll';    icon = [char]::ConvertFromUtf32(0x21CA); title = 'Cargar todo'; desc = 'Descarga todas las páginas del blog al arrancar.'; tip = "Al abrir el monitor encadena automáticamente todas las páginas disponibles del blog, no solo la primera.`n`nPuede tardar varios minutos y consume más red. También puedes hacerlo a mano con el botón «Cargar todo»." },
        @{ key = 'rememberSearch'; icon = [char]::ConvertFromUtf32(0x2315); title = 'Recordar búsqueda'; desc = 'Conserva el último filtro entre sesiones.'; tip = "Guarda el texto del buscador y lo vuelve a aplicar la próxima vez que abras la app, tanto en la ventana como en el panel de la bandeja." },
        @{ key = 'neonCycle';      icon = [char]::ConvertFromUtf32(0x2726); title = 'Neón rotativo'; desc = 'El borde cambia de color entre equipos.'; tip = "El borde animado del reproductor va rotando por los colores de equipos históricos de F1: Ferrari, McLaren, Mercedes, Red Bull, Williams, Lotus...`n`nCada 12 segundos cambia al siguiente equipo." },
        @{ key = 'cleanPlayer';    icon = [char]::ConvertFromUtf32(0x232B); title = 'Limpiar anuncios'; desc = 'Bloquea pop-ups y saltos de edad.'; tip = "Inyecta el limpiador en el reproductor incrustado: cierra ventanas emergentes, bloquea redirecciones y supera la puerta de edad automáticamente.`n`nSe aplica al reiniciar la app." },
        @{ key = 'trayHint';       icon = [char]::ConvertFromUtf32(0x25C8); title = 'Aviso de bandeja'; desc = 'Globo animado las 2 primeras veces.'; tip = "La primera y la segunda vez que abras la app se muestra un globo junto al icono de la bandeja recordando que puedes hacer clic para abrir la ventana o clic derecho para ver las opciones.`n`nSe desactiva solo si usas el clic derecho." },
        @{ key = 'sourcesEnabled'; icon = [char]::ConvertFromUtf32(0x21C5); title = 'Catálogo de fuentes'; desc = 'Añade opciones publicadas en sources.json.'; tip = "Combina las fuentes del blog con las que publiques en el catálogo (por ejemplo, un archivo sources.json en GitHub).`n`nAsí puedes añadir o actualizar reproductores sin volver a escrapear las entradas." }
    )
    foreach ($t in $tiles) {
        $tile = New-SettingTile -Key $t.key -Icon $t.icon -Title $t.title -Desc $t.desc -Tip $t.tip
        [void]$content.Controls.Add($tile)
    }

    # --- Catálogo de fuentes: URL editable + descarga manual --------------
    $cat = New-Object System.Windows.Forms.Panel
    $cat.Size = New-Object System.Drawing.Size(570, 116)
    $cat.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 10)
    $cat.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)

    $catBar = New-Object System.Windows.Forms.Panel
    $catBar.Location = New-Object System.Drawing.Point(0, 0)
    $catBar.Size = New-Object System.Drawing.Size(4, 116)
    $catBar.BackColor = $accent
    [void]$cat.Controls.Add($catBar)

    $catTitle = New-Object System.Windows.Forms.Label
    $catTitle.Text = 'CATÁLOGO DE FUENTES'
    $catTitle.AutoSize = $false
    $catTitle.Font = New-Object System.Drawing.Font('Segoe UI', 8.6, [System.Drawing.FontStyle]::Bold)
    $catTitle.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $catTitle.Location = New-Object System.Drawing.Point(16, 10)
    $catTitle.Size = New-Object System.Drawing.Size(260, 18)
    [void]$cat.Controls.Add($catTitle)

    $catDesc = New-Object System.Windows.Forms.Label
    $catDesc.Text = 'Archivo JSON con servicios y reglas. Puedes alojarlo en GitHub y editarlo sin recompilar.'
    $catDesc.AutoSize = $false
    $catDesc.Font = New-Object System.Drawing.Font('Segoe UI', 7.4)
    $catDesc.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 156)
    $catDesc.Location = New-Object System.Drawing.Point(16, 28)
    $catDesc.Size = New-Object System.Drawing.Size(540, 16)
    [void]$cat.Controls.Add($catDesc)

    $catFrame = New-Object System.Windows.Forms.Panel
    $catFrame.Location = New-Object System.Drawing.Point(16, 48)
    $catFrame.Size = New-Object System.Drawing.Size(448, 32)
    $catFrame.BackColor = [System.Drawing.Color]::FromArgb(52, 52, 66)
    $catFrame.Padding = New-Object System.Windows.Forms.Padding(1)
    [void]$cat.Controls.Add($catFrame)

    $catBox = New-Object System.Windows.Forms.TextBox
    $catBox.BorderStyle = 'None'
    $catBox.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 34)
    $catBox.ForeColor = [System.Drawing.Color]::FromArgb(232, 232, 240)
    $catBox.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $catBox.Text = [string]$script:Config.sourcesUrl
    $catBox.Dock = 'Fill'
    $catBox.Margin = New-Object System.Windows.Forms.Padding(6, 6, 6, 6)
    [void]$catFrame.Controls.Add($catBox)
    $script:SettingsSourcesBox = $catBox

    $catBtn = New-Object System.Windows.Forms.Button
    $catBtn.Text = 'Actualizar'
    $catBtn.FlatStyle = 'Flat'
    $catBtn.FlatAppearance.BorderSize = 1
    $catBtn.FlatAppearance.BorderColor = $accent
    $catBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [int]([Math]::Max(0, $accent.R * 0.22)), [int]([Math]::Max(0, $accent.G * 0.22)), [int]([Math]::Max(0, $accent.B * 0.22)))
    $catBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $catBtn.ForeColor = $accent
    $catBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.4, [System.Drawing.FontStyle]::Bold)
    $catBtn.Location = New-Object System.Drawing.Point(472, 48)
    $catBtn.Size = New-Object System.Drawing.Size(82, 32)
    $catBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    [void]$cat.Controls.Add($catBtn)
    $script:SettingsSourcesBtn = $catBtn

    $catStatus = New-Object System.Windows.Forms.Label
    $catStatus.AutoSize = $false
    $catStatus.Font = New-Object System.Drawing.Font('Segoe UI', 7.3)
    $catStatus.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 146)
    $catStatus.Location = New-Object System.Drawing.Point(18, 87)
    $catStatus.Size = New-Object System.Drawing.Size(536, 18)
    $script:SettingsSourcesStatus = $catStatus
    [void]$cat.Controls.Add($catStatus)
    Update-SourcesStatusLabel

    $catBox.Add_Leave({
        $url = ([string]$this.Text).Trim()
        if (-not $url) { $url = $script:SourcesDefaultUrl }
        $this.Text = $url
        if ($url -ne [string]$script:Config.sourcesUrl) {
            $script:Config.sourcesUrl = $url
            Save-Config
            Write-Log "Catalogo: URL cambiada a $url"
            Update-SourcesStatusLabel
        }
    })
    $catBox.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $e.SuppressKeyPress = $true
            if ($script:SettingsSourcesBtn) { $script:SettingsSourcesBtn.PerformClick() }
        }
    })
    $catBtn.Add_Click({
        if ($script:SettingsSourcesBox) {
            $url = ([string]$script:SettingsSourcesBox.Text).Trim()
            if (-not $url) { $url = $script:SourcesDefaultUrl }
            $script:SettingsSourcesBox.Text = $url
            $script:Config.sourcesUrl = $url
            Save-Config
        }
        if (-not $script:Config.sourcesEnabled) {
            $script:Config.sourcesEnabled = $true
            Save-Config
            [void](Sync-SettingsTiles)
        }
        $script:SourcesManual = $true
        Update-SourcesStatusLabel 'Descargando catálogo...'
        Start-SourcesDownload -Force
    })
    if ($script:Tip) {
        $script:Tip.SetToolTip($catBox, "Dirección del archivo sources.json.`n`nPuede ser una URL de GitHub (raw), una ruta local o una URL corporativa. Se guarda al salir del campo.")
        $script:Tip.SetToolTip($catBtn, "Descarga el catálogo ahora y reaplica sus fuentes al listado y al panel de bandeja.")
    }
    [void]$content.Controls.Add($cat)
    [void]$content.Controls.SetChildIndex($cat, 0)

    # --- Mantenimiento: version, registro y copias de ajustes --------------
    $maint = New-Object System.Windows.Forms.Panel
    $maint.Size = New-Object System.Drawing.Size(570, 150)
    $maint.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 10)
    $maint.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)

    $maintBar = New-Object System.Windows.Forms.Panel
    $maintBar.Location = New-Object System.Drawing.Point(0, 0)
    $maintBar.Size = New-Object System.Drawing.Size(4, 150)
    $maintBar.BackColor = $accent
    [void]$maint.Controls.Add($maintBar)

    $maintTitle = New-Object System.Windows.Forms.Label
    $maintTitle.Text = 'MANTENIMIENTO'
    $maintTitle.AutoSize = $false
    $maintTitle.Font = New-Object System.Drawing.Font('Segoe UI', 8.6, [System.Drawing.FontStyle]::Bold)
    $maintTitle.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $maintTitle.Location = New-Object System.Drawing.Point(16, 10)
    $maintTitle.Size = New-Object System.Drawing.Size(220, 18)
    [void]$maint.Controls.Add($maintTitle)

    $maintDesc = New-Object System.Windows.Forms.Label
    $maintDesc.Text = 'Registro, copias portables de ajustes y comprobación de versiones.'
    $maintDesc.AutoSize = $false
    $maintDesc.Font = New-Object System.Drawing.Font('Segoe UI', 7.4)
    $maintDesc.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 156)
    $maintDesc.Location = New-Object System.Drawing.Point(16, 28)
    $maintDesc.Size = New-Object System.Drawing.Size(470, 16)
    [void]$maint.Controls.Add($maintDesc)

    $maintVer = New-Object System.Windows.Forms.Label
    $maintVer.Text = "v$($script:AppVersion)"
    $maintVer.AutoSize = $false
    $maintVer.TextAlign = 'MiddleRight'
    $maintVer.Font = New-Object System.Drawing.Font('Segoe UI', 8.2, [System.Drawing.FontStyle]::Bold)
    $maintVer.ForeColor = $accent
    $maintVer.Location = New-Object System.Drawing.Point(470, 9)
    $maintVer.Size = New-Object System.Drawing.Size(84, 18)
    $script:SettingsVersionLbl = $maintVer
    [void]$maint.Controls.Add($maintVer)

    $maintFolder = New-Object System.Windows.Forms.Label
    $maintFolder.Text = 'Abrir carpeta'
    $maintFolder.AutoSize = $false
    $maintFolder.TextAlign = 'MiddleRight'
    $maintFolder.Font = New-Object System.Drawing.Font('Segoe UI', 7.4)
    $maintFolder.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 148)
    $maintFolder.Location = New-Object System.Drawing.Point(360, 9)
    $maintFolder.Size = New-Object System.Drawing.Size(102, 18)
    $maintFolder.Cursor = [System.Windows.Forms.Cursors]::Hand
    $maintFolder.Add_MouseEnter({ $this.ForeColor = [System.Drawing.Color]::FromArgb(205, 205, 218) })
    $maintFolder.Add_MouseLeave({ $this.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 148) })
    $maintFolder.Add_Click({ try { Start-Process explorer.exe $scriptDir } catch { } })
    [void]$maint.Controls.Add($maintFolder)

    $logBtn = New-Object System.Windows.Forms.Button
    $logBtn.Text = 'Ver registro'
    $logBtn.FlatStyle = 'Flat'
    $logBtn.FlatAppearance.BorderSize = 1
    $logBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $logBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $logBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $logBtn.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $logBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.2, [System.Drawing.FontStyle]::Bold)
    $logBtn.Location = New-Object System.Drawing.Point(16, 50)
    $logBtn.Size = New-Object System.Drawing.Size(108, 30)
    $logBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $logBtn.Add_Click({ Show-LogViewer })
    [void]$maint.Controls.Add($logBtn)

    $expBtn = New-Object System.Windows.Forms.Button
    $expBtn.Text = 'Exportar'
    $expBtn.FlatStyle = 'Flat'
    $expBtn.FlatAppearance.BorderSize = 1
    $expBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $expBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $expBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $expBtn.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $expBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
    $expBtn.Location = New-Object System.Drawing.Point(132, 50)
    $expBtn.Size = New-Object System.Drawing.Size(94, 30)
    $expBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $expBtn.Add_Click({ Export-Settings })
    [void]$maint.Controls.Add($expBtn)

    $impBtn = New-Object System.Windows.Forms.Button
    $impBtn.Text = 'Importar'
    $impBtn.FlatStyle = 'Flat'
    $impBtn.FlatAppearance.BorderSize = 1
    $impBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $impBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $impBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $impBtn.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $impBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
    $impBtn.Location = New-Object System.Drawing.Point(234, 50)
    $impBtn.Size = New-Object System.Drawing.Size(94, 30)
    $impBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $impBtn.Add_Click({ Import-Settings })
    [void]$maint.Controls.Add($impBtn)

    $chkBtn = New-Object System.Windows.Forms.Button
    $chkBtn.Text = 'Buscar versión'
    $chkBtn.FlatStyle = 'Flat'
    $chkBtn.FlatAppearance.BorderSize = 1
    $chkBtn.FlatAppearance.BorderColor = $accent
    $chkBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [int]([Math]::Max(0, $accent.R * 0.22)), [int]([Math]::Max(0, $accent.G * 0.22)), [int]([Math]::Max(0, $accent.B * 0.22)))
    $chkBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $chkBtn.ForeColor = $accent
    $chkBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.2, [System.Drawing.FontStyle]::Bold)
    $chkBtn.Location = New-Object System.Drawing.Point(336, 50)
    $chkBtn.Size = New-Object System.Drawing.Size(112, 30)
    $chkBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $chkBtn.Add_Click({ Start-UpdateCheck -Manual $true })
    [void]$maint.Controls.Add($chkBtn)

    $maintStatus = New-Object System.Windows.Forms.Label
    $maintStatus.Text = ''
    $maintStatus.AutoSize = $false
    $maintStatus.TextAlign = 'MiddleLeft'
    $maintStatus.Font = New-Object System.Drawing.Font('Segoe UI', 7.3)
    $maintStatus.ForeColor = [System.Drawing.Color]::FromArgb(138, 138, 154)
    $maintStatus.Location = New-Object System.Drawing.Point(16, 86)
    $maintStatus.Size = New-Object System.Drawing.Size(536, 18)
    $script:SettingsMaintStatus = $maintStatus
    [void]$maint.Controls.Add($maintStatus)

    $updStatus = New-Object System.Windows.Forms.Label
    $updStatus.Text = 'Sin comprobar todavía.'
    $updStatus.AutoSize = $false
    $updStatus.TextAlign = 'MiddleLeft'
    $updStatus.Font = New-Object System.Drawing.Font('Segoe UI', 7.4)
    $updStatus.ForeColor = [System.Drawing.Color]::FromArgb(138, 138, 154)
    $updStatus.Location = New-Object System.Drawing.Point(16, 106)
    $updStatus.Size = New-Object System.Drawing.Size(340, 18)
    $script:SettingsUpdateStatus = $updStatus
    [void]$maint.Controls.Add($updStatus)

    $updLink = New-Object System.Windows.Forms.Label
    $updLink.Text = 'Abrir descarga'
    $updLink.AutoSize = $false
    $updLink.TextAlign = 'MiddleLeft'
    $updLink.Font = New-Object System.Drawing.Font('Segoe UI', 7.6, [System.Drawing.FontStyle]::Underline)
    $updLink.ForeColor = $accent
    $updLink.Location = New-Object System.Drawing.Point(364, 106)
    $updLink.Size = New-Object System.Drawing.Size(110, 18)
    $updLink.Cursor = [System.Windows.Forms.Cursors]::Hand
    $updLink.Visible = $false
    $updLink.Add_Click({
        if ($script:UpdateUrl) { try { Start-Process $script:UpdateUrl } catch { } }
    })
    $script:SettingsUpdateLink = $updLink
    [void]$maint.Controls.Add($updLink)

    $updToggle = New-Object System.Windows.Forms.Label
    $updToggle.AutoSize = $false
    $updToggle.TextAlign = 'MiddleLeft'
    $updToggle.Font = New-Object System.Drawing.Font('Segoe UI', 7.4)
    $updToggle.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 148)
    $updToggle.Location = New-Object System.Drawing.Point(16, 126)
    $updToggle.Size = New-Object System.Drawing.Size(300, 18)
    $updToggle.Cursor = [System.Windows.Forms.Cursors]::Hand
    $script:SettingsMaintToggle = $updToggle
    [void]$maint.Controls.Add($updToggle)

    $syncToggle = {
        if ($script:SettingsMaintToggle) {
            $on = [bool]$script:Config.updateCheck
            $script:SettingsMaintToggle.Text = "Avisar de versiones nuevas al iniciar: $(if ($on) { 'Sí' } else { 'No' })"
            $script:SettingsMaintToggle.ForeColor = if ($on) { [System.Drawing.Color]::FromArgb(150, 150, 168) } else { [System.Drawing.Color]::FromArgb(110, 110, 126) }
        }
    }
    $updToggle.Add_Click({
        $script:Config.updateCheck = -not [bool]$script:Config.updateCheck
        Save-Config
        & $syncToggle
        if ($script:Config.updateCheck) { Start-UpdateAutoCheck }
        else { $script:UpdateStatusText = 'Avisos de versión desactivados.'; Update-SettingsUpdateUI }
        Write-Log "Aviso de actualizaciones: $($script:Config.updateCheck)"
    })
    & $syncToggle

    if ($script:Tip) {
        $script:Tip.SetToolTip($logBtn, 'Abre monitor.log en un visor oscuro con copia al portapapeles.')
        $script:Tip.SetToolTip($expBtn, 'Guarda configuración, favoritos, búsquedas y catálogo en un único JSON.')
        $script:Tip.SetToolTip($impBtn, 'Aplica un JSON exportado desde otro equipo. Sustituye la configuración actual.')
        $script:Tip.SetToolTip($chkBtn, 'Consulta GitHub Releases sin bloquear la ventana. No descarga nada.')
        $script:Tip.SetToolTip($maintVer, 'Versión instalada de F1 Tray Monitor.')
        $script:Tip.SetToolTip($maintFolder, 'Abre la carpeta de la app en el Explorador.')
    }

    Update-SettingsUpdateUI
    [void]$content.Controls.Add($maint)

    # --- Barra inferior: intervalo + neon ----------------------------------
    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'
    $bottom.Height = 150
    $bottom.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 24)
    [void]$shell.Controls.Add($bottom)

    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text = 'Comprobar nuevas entradas cada'
    $lbl1.AutoSize = $false
    $lbl1.TextAlign = 'MiddleLeft'
    $lbl1.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 220)
    $lbl1.Location = New-Object System.Drawing.Point(18, 14)
    $lbl1.Size = New-Object System.Drawing.Size(238, 26)
    [void]$bottom.Controls.Add($lbl1)

    # Stepper propio: marco tenue, panel oscuro y botones − / + alineados.
    $stepFrame = New-Object System.Windows.Forms.Panel
    $stepFrame.Location = New-Object System.Drawing.Point(270, 11)
    $stepFrame.Size = New-Object System.Drawing.Size(152, 34)
    $stepFrame.BackColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $stepFrame.Padding = New-Object System.Windows.Forms.Padding(1)
    [void]$bottom.Controls.Add($stepFrame)

    $stepPanel = New-Object System.Windows.Forms.Panel
    $stepPanel.Dock = 'Fill'
    $stepPanel.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 34)
    [void]$stepFrame.Controls.Add($stepPanel)

    $minus = New-Object System.Windows.Forms.Button
    $minus.Text = '-'
    $minus.FlatStyle = 'Flat'
    $minus.FlatAppearance.BorderSize = 0
    $minus.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(40, 40, 52)
    $minus.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 34)
    $minus.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 235)
    $minus.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $minus.Location = New-Object System.Drawing.Point(1, 1)
    $minus.Size = New-Object System.Drawing.Size(30, 30)
    $minus.Cursor = [System.Windows.Forms.Cursors]::Hand
    $minus.TabStop = $false
    $minus.Add_Click({
        $v = [Math]::Max(1, [int]$script:Config.intervalMinutes - 1)
        $script:Config.intervalMinutes = $v
        Save-Config
        if ($script:MainTimer) { $script:MainTimer.Interval = $v * 60 * 1000 }
        if ($script:SettingsIntervalLbl) { $script:SettingsIntervalLbl.Text = "$v min" }
    })
    [void]$stepPanel.Controls.Add($minus)

    $val = New-Object System.Windows.Forms.Label
    $val.Text = "$([int]$script:Config.intervalMinutes) min"
    $val.AutoSize = $false
    $val.TextAlign = 'MiddleCenter'
    $val.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $val.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 246)
    $val.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 34)
    $val.Location = New-Object System.Drawing.Point(33, 0)
    $val.Size = New-Object System.Drawing.Size(84, 32)
    [void]$stepPanel.Controls.Add($val)
    $script:SettingsIntervalLbl = $val

    $plus = New-Object System.Windows.Forms.Button
    $plus.Text = '+'
    $plus.FlatStyle = 'Flat'
    $plus.FlatAppearance.BorderSize = 0
    $plus.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(40, 40, 52)
    $plus.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 34)
    $plus.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 235)
    $plus.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $plus.Location = New-Object System.Drawing.Point(119, 1)
    $plus.Size = New-Object System.Drawing.Size(30, 30)
    $plus.Cursor = [System.Windows.Forms.Cursors]::Hand
    $plus.TabStop = $false
    $plus.Add_Click({
        $v = [Math]::Min(180, [int]$script:Config.intervalMinutes + 1)
        $script:Config.intervalMinutes = $v
        Save-Config
        if ($script:MainTimer) { $script:MainTimer.Interval = $v * 60 * 1000 }
        if ($script:SettingsIntervalLbl) { $script:SettingsIntervalLbl.Text = "$v min" }
    })
    [void]$stepPanel.Controls.Add($plus)

    if ($script:Tip) {
        foreach ($c in @($stepFrame, $minus, $val, $plus)) {
            $script:Tip.SetToolTip($c, 'Minutos entre comprobaciones (1–180). Usa − y + para ajustarlo.')
        }
    }

    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Text = 'Neón del reproductor'
    $lbl2.AutoSize = $false
    $lbl2.TextAlign = 'MiddleLeft'
    $lbl2.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 220)
    $lbl2.Location = New-Object System.Drawing.Point(18, 58)
    $lbl2.Size = New-Object System.Drawing.Size(238, 26)
    [void]$bottom.Controls.Add($lbl2)

    $neonIdx = 0
    for ($i = 0; $i -lt $script:NeonTeams.Count; $i++) {
        if ($script:NeonTeams[$i].key -eq $script:Config.neonTeam) { $neonIdx = $i; break }
    }
    $neonBtn = New-Object System.Windows.Forms.Button
    $neonBtn.Text = "$([char]::ConvertFromUtf32(0x25CF))  $($script:NeonTeams[$neonIdx].name)"
    $neonBtn.FlatStyle = 'Flat'
    $neonBtn.FlatAppearance.BorderSize = 1
    $neonBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $neonBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $neonBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $neonBtn.ForeColor = Get-NeonColor
    $neonBtn.Font = New-Object System.Drawing.Font('Segoe UI', 9.2)
    $neonBtn.TextAlign = 'MiddleLeft'
    $neonBtn.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $neonBtn.Location = New-Object System.Drawing.Point(270, 55)
    $neonBtn.Size = New-Object System.Drawing.Size(220, 34)
    $neonBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $script:SettingsNeonBtn = $neonBtn
    if ($script:Tip) { $script:Tip.SetToolTip($neonBtn, 'Clic para pasar al siguiente equipo. El color se aplica a toda la paleta del reproductor y al marco de este panel.') }
    $neonBtn.Add_Click({
        $keys = @($script:NeonTeams | ForEach-Object { $_.key })
        $i = [Array]::IndexOf($keys, [string]$script:Config.neonTeam)
        if ($i -lt 0) { $i = 0 }
        $i = ($i + 1) % $keys.Count
        $script:Config.neonTeam = [string]$keys[$i]
        Save-Config
        Apply-Neon
        Apply-NeonToWindow
        if ($script:SettingsNeonBtn) {
            $script:SettingsNeonBtn.Text = "$([char]::ConvertFromUtf32(0x25CF))  $($script:NeonTeams[$i].name)"
            $script:SettingsNeonBtn.ForeColor = Get-NeonColor
        }
        try { $script:SettingsForm.BackColor = Get-NeonColor } catch { }
    })
    [void]$bottom.Controls.Add($neonBtn)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'El neón tiñe toda la paleta del vídeo incrustado y el marco de este panel.'
    $hint.AutoSize = $false
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 7.8)
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 145)
    $hint.Location = New-Object System.Drawing.Point(18, 102)
    $hint.Size = New-Object System.Drawing.Size(420, 20)
    [void]$bottom.Controls.Add($hint)

    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = 'Cerrar'
    $closeBtn.FlatStyle = 'Flat'
    $closeBtn.FlatAppearance.BorderSize = 1
    $closeBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $closeBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $closeBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $closeBtn.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $closeBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.8, [System.Drawing.FontStyle]::Bold)
    $closeBtn.Size = New-Object System.Drawing.Size(104, 32)
    $closeBtn.Location = New-Object System.Drawing.Point(500, 106)
    $closeBtn.Anchor = 'Bottom,Right'
    $closeBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeBtn.Add_Click({ $script:SettingsForm.Close() })
    [void]$bottom.Controls.Add($closeBtn)

    $f.Add_FormClosed({
        $script:SettingsForm = $null
        $script:SettingsNeonBtn = $null
        $script:SettingsIntervalLbl = $null
        $script:SettingsSourcesBox = $null
        $script:SettingsSourcesBtn = $null
        $script:SettingsSourcesStatus = $null
        $script:SettingsTiles = $null
        $script:SettingsUpdateStatus = $null
        $script:SettingsUpdateLink = $null
        $script:SettingsMaintStatus = $null
        $script:SettingsMaintToggle = $null
        $script:SettingsVersionLbl = $null
    })
    $f.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $this.Close() }
    })
    $f.KeyPreview = $true
    # Orden de acoplado: contenido Fill primero, luego barra inferior y cabecera.
    [void]$shell.Controls.SetChildIndex($content, 0)
    [void]$shell.Controls.SetChildIndex($bottom, 1)
    [void]$shell.Controls.SetChildIndex($head, 2)
    $f.Show()
    $f.Activate()
}

# --- Ventana: tarjetas desplegables ---------------------------------------
function New-CardChip {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [System.Drawing.Color]$Back,
        [System.Drawing.Color]$Fore
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $false
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.Font = $script:FontChip
    $lbl.Text = $Text
    $lbl.Size = [System.Drawing.Size]::new($Width, 18)
    $lbl.Location = [System.Drawing.Point]::new($X, $Y)
    $lbl.BackColor = $Back
    $lbl.ForeColor = $Fore
    return $lbl
}

function New-Card {
    param($Post)

    $id        = [string]$Post.id
    $type      = [string]$Post.type
    $short     = Get-ShortTitle ([string]$Post.title)
    $meta      = Get-RaceMeta -Title ([string]$Post.title)
    $typeColor = Get-TypeColor -Type $type -Hex ([string]$Post.badge_color)
    $opts      = @(Get-PlayOptions $Post)
    $cardW     = 760
    $cardH     = 88

    $card = New-Object System.Windows.Forms.Panel
    $card.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $card.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 10)
    $card.Tag = [PSCustomObject]@{ id = $id; color = $typeColor }
    $card.Cursor = [System.Windows.Forms.Cursors]::Hand
    $card.Add_Click({ Toggle-Card -Id ([string]$this.Tag.id) })
    $card.Add_MouseEnter({ $this.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 33) })
    $card.Add_MouseLeave({ $this.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24) })
    $card.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = $s.Width
        $h = $s.Height
        $c = [System.Drawing.Color]$s.Tag.color
        $glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24, $c))
        $g.FillRectangle($glow, 0, 0, [Math]::Min(260, $w), $h)
        $glow.Dispose()
        $stripe = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(14, 255, 255, 255)), 1
        for ($x = $w - 210; $x -lt $w + 60; $x += 18) {
            $g.DrawLine($stripe, $x, 0, $x - 58, $h)
        }
        $stripe.Dispose()
        $line = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(38, 255, 255, 255)), 1
        $g.DrawLine($line, 0, $h - 1, $w, $h - 1)
        $line.Dispose()
    })

    $accent = New-Object System.Windows.Forms.Panel
    $accent.BackColor = $typeColor
    $accent.Location = [System.Drawing.Point]::new(0, 0)
    $accent.Size = [System.Drawing.Size]::new(5, $cardH)
    $card.Controls.Add($accent)

    # Placa de ronda inclinada, como el numero de un coche en la parrilla.
    $numBox = New-Object System.Windows.Forms.Panel
    $numBox.Location = [System.Drawing.Point]::new(16, 16)
    $numBox.Size = [System.Drawing.Size]::new(56, 56)
    $numBox.BackColor = [System.Drawing.Color]::Transparent
    $numBox.Cursor = [System.Windows.Forms.Cursors]::Hand
    $numText = if ($meta.Round) { [string]$meta.Round } else { [char]::ConvertFromUtf32(0x2014) }
    $numBox.Tag = [PSCustomObject]@{ num = $numText; cc = [string]$meta.Cc; color = $typeColor }
    $numBox.Add_Click({ Toggle-Card -Id ([string]$this.Parent.Tag.id) })
    $numBox.Add_MouseEnter({ $this.Parent.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 33) })
    $numBox.Add_MouseLeave({ $this.Parent.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24) })
    $numBox.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $t = $s.Tag
        $w = $s.Width
        $h = $s.Height
        $r = [int]$t.color.R
        $gr = [int]$t.color.G
        $b = [int]$t.color.B
        $light = [System.Drawing.Color]::FromArgb(
            [Math]::Min(255, $r + 38), [Math]::Min(255, $gr + 38), [Math]::Min(255, $b + 38))
        $dark = [System.Drawing.Color]::FromArgb(
            [int]($r * 0.52), [int]($gr * 0.52), [int]($b * 0.52))
        $pts = @(
            (New-Object System.Drawing.Point(9, 0)),
            (New-Object System.Drawing.Point($w, 0)),
            (New-Object System.Drawing.Point(($w - 9), $h)),
            (New-Object System.Drawing.Point(0, $h))
        )
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0, 0)),
            (New-Object System.Drawing.Point($w, $h)),
            $light, $dark)
        $g.FillPolygon($brush, $pts)
        $brush.Dispose()

        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString([string]$t.num, $script:FontNum, [System.Drawing.Brushes]::White,
            (New-Object System.Drawing.RectangleF(0, -7, $w, $h)), $fmt)
        $ccBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225, 255, 255, 255))
        $g.DrawString([string]$t.cc, $script:FontCc, $ccBrush,
            (New-Object System.Drawing.RectangleF(0, 18, $w, 16)), $fmt)
        $ccBrush.Dispose()
        $fmt.Dispose()
    })
    $card.Controls.Add($numBox)

    $gpText = if ($meta.IsF1) { [string]$meta.Gp } else { $short.ToUpperInvariant() }
    $gp = New-Object System.Windows.Forms.Label
    $gp.AutoSize = $false
    $gp.AutoEllipsis = $true
    $gp.BackColor = [System.Drawing.Color]::Transparent
    $gp.ForeColor = [System.Drawing.Color]::FromArgb(246, 246, 250)
    $gp.Font = $script:FontGp
    $gp.TextAlign = 'MiddleLeft'
    $gp.Location = [System.Drawing.Point]::new(86, 8)
    $gp.Size = [System.Drawing.Size]::new(500, 28)
    $gp.Text = $gpText
    $gp.Cursor = [System.Windows.Forms.Cursors]::Hand
    $gp.Add_Click({ Toggle-Card -Id ([string]$this.Parent.Tag.id) })
    $gp.Add_MouseEnter({ $this.Parent.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 33) })
    $gp.Add_MouseLeave({ $this.Parent.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24) })
    $card.Controls.Add($gp)

    $dot = [char]::ConvertFromUtf32(0x00B7)
    $circuitText = if ($meta.IsF1) {
        ("{0}  {1}  {2}" -f ([string]$meta.Circuit).ToUpperInvariant(), $dot, ([string]$meta.City).ToUpperInvariant())
    }
    else { 'EVENTO ESPECIAL' }
    $circuit = New-Object System.Windows.Forms.Label
    $circuit.AutoSize = $false
    $circuit.AutoEllipsis = $true
    $circuit.BackColor = [System.Drawing.Color]::Transparent
    $circuit.ForeColor = [System.Drawing.Color]::FromArgb(138, 138, 154)
    $circuit.Font = $script:FontCircuit
    $circuit.TextAlign = 'MiddleLeft'
    $circuit.Location = [System.Drawing.Point]::new(86, 36)
    $circuit.Size = [System.Drawing.Size]::new(500, 16)
    $circuit.Text = $circuitText
    $circuit.Cursor = [System.Windows.Forms.Cursors]::Hand
    $circuit.Add_Click({ Toggle-Card -Id ([string]$this.Parent.Tag.id) })
    $circuit.Add_MouseEnter({ $this.Parent.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 33) })
    $circuit.Add_MouseLeave({ $this.Parent.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24) })
    $card.Controls.Add($circuit)

    # Chips: ano, sesion, catalogo y numero de fuentes.
    $mutedBack = [System.Drawing.Color]::FromArgb(27, 27, 35)
    $mutedFore = [System.Drawing.Color]::FromArgb(158, 158, 174)
    $lum = 0.299 * [int]$typeColor.R + 0.587 * [int]$typeColor.G + 0.114 * [int]$typeColor.B
    $chipFore = if ($lum -gt 150) { [System.Drawing.Color]::FromArgb(14, 14, 18) } else { [System.Drawing.Color]::White }
    $chips = New-Object System.Collections.ArrayList
    $chipX = 86
    $chipY = 56

    if ($meta.IsF1 -and $meta.Year) {
        [void]$chips.Add((New-CardChip -Text ([string]$meta.Year) -X $chipX -Y $chipY -Width 44 -Back $mutedBack -Fore $mutedFore))
        $chipX += 50
    }
    $sessionText = $type.ToUpperInvariant()
    $sessionW = [Math]::Max(74, [System.Windows.Forms.TextRenderer]::MeasureText($sessionText, $script:FontChip).Width + 16)
    [void]$chips.Add((New-CardChip -Text $sessionText -X $chipX -Y $chipY -Width $sessionW -Back $typeColor -Fore $chipFore))
    $chipX += $sessionW + 6

    $catalogCount = @($opts | Where-Object { $_.origin -eq 'catalog' }).Count
    if ($catalogCount -gt 0) {
        $catText = if ($catalogCount -eq 1) { 'CATALOGO' } else { "CATALOGO +$catalogCount" }
        $catW = [System.Windows.Forms.TextRenderer]::MeasureText($catText, $script:FontChip).Width + 16
        $neon = Get-NeonColor
        [void]$chips.Add((New-CardChip -Text $catText -X $chipX -Y $chipY -Width $catW -Back $neon -Fore $chipFore))
        $chipX += $catW + 6
    }

    $srcText = if ($opts.Count -eq 1) { '1 FUENTE' } else { "$($opts.Count) FUENTES" }
    $srcW = [Math]::Max(74, [System.Windows.Forms.TextRenderer]::MeasureText($srcText, $script:FontChip).Width + 16)
    [void]$chips.Add((New-CardChip -Text $srcText -X $chipX -Y $chipY -Width $srcW -Back $mutedBack -Fore $mutedFore))

    foreach ($chip in $chips) {
        $chip.Cursor = [System.Windows.Forms.Cursors]::Hand
        $chip.Add_Click({ Toggle-Card -Id ([string]$this.Parent.Tag.id) })
        $card.Controls.Add($chip)
    }

    $chevron = New-Object System.Windows.Forms.Label
    $chevron.AutoSize = $false
    $chevron.TextAlign = 'MiddleCenter'
    $chevron.BackColor = [System.Drawing.Color]::Transparent
    $chevron.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 145)
    $chevron.Font = $script:FontChevron
    $chevron.Text = [char]::ConvertFromUtf32(0x25B8)
    $chevron.Location = [System.Drawing.Point]::new($cardW - 32, 32)
    $chevron.Size = [System.Drawing.Size]::new(22, 24)
    $chevron.Cursor = [System.Windows.Forms.Cursors]::Hand
    $chevron.Add_Click({ Toggle-Card -Id ([string]$this.Parent.Tag.id) })
    $card.Controls.Add($chevron)

    $favKey = Get-FavoriteKey $Post
    $favOn = Test-Favorite $favKey
    $starBtn = New-Object System.Windows.Forms.Button
    $starBtn.FlatStyle = 'Flat'
    $starBtn.FlatAppearance.BorderSize = 0
    $starBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(40, 40, 52)
    $starBtn.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $starBtn.ForeColor = if ($favOn) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(125, 125, 140) }
    $starBtn.Font = [System.Drawing.Font]::new('Segoe UI Symbol', 11)
    $starBtn.Text = if ($favOn) { [char]::ConvertFromUtf32(0x2605) } else { [char]::ConvertFromUtf32(0x2606) }
    $starBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $starBtn.Location = [System.Drawing.Point]::new($cardW - 96, 10)
    $starBtn.Size = [System.Drawing.Size]::new(26, 26)
    $starBtn.Tag = $favKey
    $starBtn.Add_Click({ Toggle-Favorite -Key ([string]$this.Tag) })
    $card.Controls.Add($starBtn)

    $openBtn = New-Object System.Windows.Forms.Button
    $openBtn.FlatStyle = 'Flat'
    $openBtn.FlatAppearance.BorderSize = 0
    $openBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(40, 40, 52)
    $openBtn.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $openBtn.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 156)
    $openBtn.Font = [System.Drawing.Font]::new('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $openBtn.Text = [char]::ConvertFromUtf32(0x2197)
    $openBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $openBtn.Location = [System.Drawing.Point]::new($cardW - 64, 10)
    $openBtn.Size = [System.Drawing.Size]::new(26, 26)
    $openBtn.Tag = [string]$Post.url
    $openBtn.Add_Click({ try { Start-Process ([string]$this.Tag) } catch { Write-Log "Error abriendo entrada: $_" } })
    $card.Controls.Add($openBtn)

    $rows = [Math]::Max(1, $opts.Count)
    $optsH = 12 + ($rows * 40) + 36

    $srcList = @()
    foreach ($o in $opts) {
        $srcList += [PSCustomObject]@{
            name       = [string]$o.name
            url        = [string]$o.player_url
            service    = [string]$o.service
            serviceKey = [string]$o.serviceKey
            color      = [string]$o.color
            quality    = [string]$o.quality
            lang       = [string]$o.lang
            primary    = [bool]$o.primary
            origin     = [string]$o.origin
        }
    }

    $panel = New-Object System.Windows.Forms.Panel
    $panel.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 17)
    $panel.Location = [System.Drawing.Point]::new(6, $cardH)
    $panel.Size = [System.Drawing.Size]::new($cardW - 6, $optsH)
    $panel.Visible = $false
    $panel.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(42, 255, 255, 255)), 1
        $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
        $pen.Dispose()
    })

    # Las opciones se crean la primera vez que la tarjeta se despliega. Con 246
    # entradas se evitan mas de mil controles en el listado inicial.
    [void]$card.Controls.Add($panel)

    if ($script:Tip) {
        $script:Tip.SetToolTip($gp, [string]$Post.title)
        $script:Tip.SetToolTip($circuit, [string]$Post.title)
        $script:Tip.SetToolTip($openBtn, 'Abrir la entrada original en el navegador')
        $script:Tip.SetToolTip($starBtn, 'Marcar o quitar de favoritos')
    }

    return @{
        Id            = $id
        Card          = $card
        Chevron       = $chevron
        NumBox        = $numBox
        Gp            = $gp
        Circuit       = $circuit
        Options       = $panel
        OptionsBuilt  = $false
        Opts          = @($opts)
        SrcList       = @($srcList)
        Rows          = $rows
        PostType      = $type
        Url           = [string]$Post.url
        OpenBtn       = $openBtn
        StarBtn       = $starBtn
        FavKey        = $favKey
        BlogBtn       = $null
        OptionButtons = (New-Object System.Collections.ArrayList)
        ClosedHeight  = $cardH
        OpenHeight    = $cardH + $optsH
        Title         = [string]$Post.title
    }
}

# Rellena las opciones de una tarjeta la primera vez que se abre.
function Build-CardOptionButtons {
    param($C)

    if ($C.OptionsBuilt -or -not $C.Options -or $C.Options.IsDisposed) { return }
    $C.OptionsBuilt = $true

    $inner = [Math]::Max(180, [int]$C.Card.Width - 36)
    $opts = @($C.Opts)

    if ($opts.Count -eq 0) {
        $emptyLbl = New-Object System.Windows.Forms.Label
        $emptyLbl.Text = 'Sin opciones de reproduccion para esta entrada'
        $emptyLbl.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 152)
        $emptyLbl.Font = [System.Drawing.Font]::new('Segoe UI', 8.5)
        $emptyLbl.Location = [System.Drawing.Point]::new(14, 14)
        $emptyLbl.Size = [System.Drawing.Size]::new([Math]::Max(200, $inner - 28), 24)
        [void]$C.Options.Controls.Add($emptyLbl)
    }
    else {
        $i = 0
        foreach ($opt in $opts) {
            $ob = New-Object System.Windows.Forms.Button
            $ob.FlatStyle = 'Flat'
            $ob.FlatAppearance.BorderSize = 0
            $ob.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 38, 50)
            $ob.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(48, 48, 62)
            $ob.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
            $ob.ForeColor = [System.Drawing.Color]::FromArgb(222, 222, 232)
            $ob.TextAlign = 'MiddleLeft'
            $ob.Padding = [System.Windows.Forms.Padding]::new(12, 0, 10, 0)
            $ob.Font = [System.Drawing.Font]::new('Segoe UI', 9)
            $ob.UseCompatibleTextRendering = $true
            $ob.AutoEllipsis = $true
            $ob.Cursor = [System.Windows.Forms.Cursors]::Hand
            $suffix = @()
            if ($opt.quality) { $suffix += [string]$opt.quality }
            if ($opt.lang) { $suffix += [string]$opt.lang }
            $tail = if ($suffix.Count -gt 0) { '   ·   ' + ($suffix -join ' ') } else { '' }
            $ob.Text = "$([char]::ConvertFromUtf32(0x25B6))   $($i.ToString('00'))   $($opt.name)$tail"
            $ob.Location = [System.Drawing.Point]::new(12, 10 + ($i * 40))
            $ob.Size = [System.Drawing.Size]::new($inner, 34)
            $ob.Tag = [PSCustomObject]@{
                src     = [string]$opt.player_url
                title   = [string]$C.Title
                name    = [string]$opt.name
                type    = [string]$C.PostType
                sources = @($C.SrcList)
            }
            $ob.Add_Click({
                $t = $this.Tag
                Open-Player -Src $t.src -Title $t.title -Option $t.name -Type $t.type -Sources $t.sources
            })
            [void]$C.Options.Controls.Add($ob)
            [void]$C.OptionButtons.Add($ob)
            $i++
        }
    }

    $blogBtn = New-Object System.Windows.Forms.Button
    $blogBtn.FlatStyle = 'Flat'
    $blogBtn.FlatAppearance.BorderSize = 0
    $blogBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(28, 28, 38)
    $blogBtn.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 17)
    $blogBtn.ForeColor = [System.Drawing.Color]::FromArgb(145, 145, 160)
    $blogBtn.TextAlign = 'MiddleLeft'
    $blogBtn.Padding = [System.Windows.Forms.Padding]::new(12, 0, 10, 0)
    $blogBtn.Font = [System.Drawing.Font]::new('Segoe UI', 8.5)
    $blogBtn.UseCompatibleTextRendering = $true
    $blogBtn.AutoEllipsis = $true
    $blogBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $blogBtn.Text = "$([char]::ConvertFromUtf32(0x2197))   Abrir entrada en el blog"
    $blogBtn.Location = [System.Drawing.Point]::new(12, 10 + ([int]$C.Rows * 40))
    $blogBtn.Size = [System.Drawing.Size]::new($inner, 30)
    $blogBtn.Tag = [string]$C.Url
    $blogBtn.Add_Click({ try { Start-Process ([string]$this.Tag) } catch { Write-Log "Error abriendo entrada: $_" } })
    [void]$C.Options.Controls.Add($blogBtn)
    $C.BlogBtn = $blogBtn
    if ($script:Tip) { $script:Tip.SetToolTip($blogBtn, [string]$C.Url) }
}

function Update-Card {
    param($C)
    $expanded = ($C.Id -eq $script:ExpandedId)
    if ($expanded) { Build-CardOptionButtons $C }
    $C.Options.Visible = $expanded
    $C.Card.Height = if ($expanded) { $C.OpenHeight } else { $C.ClosedHeight }
    if ($C.Chevron) {
        $C.Chevron.Text = if ($expanded) { [char]::ConvertFromUtf32(0x25BE) } else { [char]::ConvertFromUtf32(0x25B8) }
        $C.Chevron.ForeColor = if ($expanded) { Get-NeonColor } else { [System.Drawing.Color]::FromArgb(130, 130, 145) }
    }
}

function Toggle-Card {
    param([string]$Id)

    # Acordeon: solo una entrada abierta a la vez. Se actualizan unicamente la
    # tarjeta que se cierra y la que se abre, no las 246 de la lista.
    $prev = $script:ExpandedId
    if ($prev -eq $Id) { $script:ExpandedId = '' }
    else { $script:ExpandedId = $Id }

    foreach ($key in @($prev, $script:ExpandedId)) {
        if (-not $key) { continue }
        if ($script:CardById.ContainsKey($key)) { Update-Card $script:CardById[$key] }
    }
    if ($script:ListFlow) { $script:ListFlow.PerformLayout() }

    # Si la entrada queda fuera de la vista, se acerca lo justo para verla.
    if ($script:ExpandedId -and $script:CardById.ContainsKey($script:ExpandedId) -and $script:ListFlow) {
        try {
            $card = $script:CardById[$script:ExpandedId].Card
            $visible = $script:ListFlow.ClientSize.Height
            if ($card.Top -lt 0 -or ($card.Top + [Math]::Min($card.Height, $visible)) -gt $visible) {
                $script:ListFlow.ScrollControlIntoView($card)
            }
        } catch { }
    }
}

function Update-StatusCounts {
    $total = $script:Posts.Count
    $visible = if ($script:ListFlow) { $script:Cards.Count } else { $total }
    if ($script:CountLbl) {
        if ($script:SearchQuery -and $visible -ne $total) { $script:CountLbl.Text = "$visible de $total entradas" }
        else { $script:CountLbl.Text = "$total entradas" }
    }
}

function Update-CardSizes {
    if (-not $script:ListFlow) { return }
    $w = $script:ListFlow.ClientSize.Width - 40
    if ($w -lt 220) { $w = 220 }

    foreach ($c in $script:Cards) {
        $c.Card.Width = $w
        $c.Options.Width = $w
        $c.OpenBtn.Left = $w - 64
        if ($c.StarBtn) { $c.StarBtn.Left = $w - 96 }
        if ($c.Chevron) { $c.Chevron.Left = $w - 32 }
        if ($c.Gp) { $c.Gp.Width = [Math]::Max(140, $w - 260) }
        if ($c.Circuit) { $c.Circuit.Width = [Math]::Max(140, $w - 260) }
        $inner = $w - 36
        foreach ($ob in $c.OptionButtons) { $ob.Width = $inner }
        if ($c.BlogBtn) { $c.BlogBtn.Width = $inner }
    }
    $script:ListFlow.PerformLayout()
}

# --- Listado: construccion cacheada y responsiva --------------------------
# Huella del catalogo: incluye el estado del ajuste y una marca del fichero
# (tamano + fecha) para invalidar las tarjetas tambien cuando se edita
# sources.json a mano sin subir la version, o al activar/desactivar el catalogo.
function Get-CatalogFingerprint {
    if (-not $script:Config.sourcesEnabled) { return 'off' }

    $stamp = ''
    foreach ($f in @($sourcesFile, $sourcesCacheFile)) {
        try {
            if (Test-Path $f) {
                $fi = Get-Item $f
                $stamp += ('{0}:{1};' -f $fi.Length, $fi.LastWriteTimeUtc.Ticks)
            }
        }
        catch { }
    }
    if (-not $script:SourcesCatalog) { return "on|sin-catalogo|$stamp" }

    $rules = @($script:SourcesCatalog.rules).Count
    $services = 0
    if ($script:SourcesCatalog.services) {
        $services = @($script:SourcesCatalog.services.PSObject.Properties).Count
    }
    return "on|$($script:SourcesCatalog.version)|$($script:SourcesCatalog.updated)|$rules|$services|$stamp"
}

# Huella de id+titulo de todas las entradas. Se calcula una vez por asignacion
# de $script:Posts: si el blog corrige un titulo, la lista se reconstruye
# aunque el numero de entradas y la primera sigan igual.
function Get-PostsFingerprint {
    if ($script:PostsHash -and [object]::ReferenceEquals($script:Posts, $script:PostsHashFor)) {
        return $script:PostsHash
    }

    $sb = New-Object System.Text.StringBuilder
    foreach ($p in @($script:Posts)) {
        [void]$sb.Append([string]$p.id).Append('|').Append([string]$p.title).Append("`n")
    }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
    }
    finally { $md5.Dispose() }

    $hex = -join @($hash | ForEach-Object { $_.ToString('x2') })
    $script:PostsHashFor = $script:Posts
    $script:PostsHash = $hex.Substring(0, 12)
    return $script:PostsHash
}

# La firma resume lo que se esta mostrando. Si no cambia, Build-List no hace
# nada: mostrar la ventana o abrir un video deja de reconstruir 246 tarjetas.
function Get-ListSignature {
    $fav = if ($script:FavoritesOnly) { $script:Favorites.Count } else { 0 }
    return "$(Get-PostsFingerprint)|$($script:SearchQuery)|$($script:FavoritesOnly)|$fav|$(Get-CatalogFingerprint)"
}

# El divisor no tiene minimos duros: se guarda una proporcion y se reaplica al
# redimensionar. Arrastrarlo hasta el borde izquierdo oculta el listado, que se
# recupera con el boton, con doble clic en el divisor o agrandando la ventana.
function Set-SplitRatio {
    param([double]$Ratio = 0.40)

    if (-not $script:Split -or $script:Split.IsDisposed) { return }
    if ($script:Split.Panel2Collapsed -or $script:Split.Panel1Collapsed) { return }
    $total = $script:Split.Width - $script:Split.SplitterWidth
    if ($total -lt 140) { return }

    $clamped = [Math]::Max(0.10, [Math]::Min(0.90, $Ratio))
    $script:SplitRatio = $clamped
    $d = [int][Math]::Round($total * $clamped)
    $d = [Math]::Max(80, [Math]::Min($total - 160, $d))
    if ([Math]::Abs($d - $script:Split.SplitterDistance) -lt 1) {
        $script:SplitTarget = $d
        return
    }
    try {
        $script:SplitDrag = $true
        $script:SplitTarget = $d
        $script:Split.SplitterDistance = $d
    }
    catch { }
    finally { $script:SplitDrag = $false }
}

# La cabecera se mide en lugar de estimarse: al ocultar los botones de video el
# ancho necesario baja a ~262 px y a 520 px de ventana caben todos. Si aun asi
# faltara sitio (DPI alto), se sacrifica primero el filtro de favoritos.
function Get-HeaderActionsWidth {
    param([bool]$ShowShorts, [bool]$HideFav)

    if (-not $script:HeaderActions) { return 0 }
    $need = $script:HeaderActions.Padding.Right
    foreach ($c in $script:HeaderActions.Controls) {
        if ($c -eq $script:VideoOnlyBtn -and -not $ShowShorts) { continue }
        if ($c -eq $script:ListToggleBtn -and -not $ShowShorts) { continue }
        if ($c -eq $script:FavFilterBtn -and $HideFav) { continue }
        $need += $c.Width + $c.Margin.Horizontal
    }
    return $need
}

# Barra de herramientas adaptativa: los botones de paginacion ceden su sitio al
# buscador antes de solaparse con el cuando la ventana se estrecha.
function Update-ToolbarLayout {
    if (-not $script:Toolbar) { return }
    $w = $script:Toolbar.ClientSize.Width
    if ($w -le 0) { return }

    $showAll = $w -ge 780
    $showPage = $w -ge 620
    if ($script:LoadAllBtn) { $script:LoadAllBtn.Visible = $showAll }
    if ($script:NextPageBtn) { $script:NextPageBtn.Visible = $showPage }

    $used = 0
    if ($script:NextPageBtn -and $showPage) {
        $script:NextPageBtn.Left = [Math]::Max(140, $w - $script:NextPageBtn.Width - 12)
        $used += $script:NextPageBtn.Width + 8
    }
    if ($script:LoadAllBtn -and $showAll -and $script:NextPageBtn) {
        $script:LoadAllBtn.Left = [Math]::Max(60, $script:NextPageBtn.Left - $script:LoadAllBtn.Width - 8)
        $used += $script:LoadAllBtn.Width + 8
    }
    if ($script:SearchWrap) {
        $script:SearchWrap.Width = [Math]::Max(130, $w - 24 - $used - 8)
    }
}

# Un unico temporizador agrupa los eventos de resize: redimensionar ya no
# recalcula 246 tarjetas decenas de veces por segundo.
function Request-Layout {
    if (-not $script:LayoutTimer) {
        $script:LayoutTimer = New-Object System.Windows.Forms.Timer
        $script:LayoutTimer.Interval = 80
        $script:LayoutTimer.Add_Tick({
            $script:LayoutTimer.Stop()
            Update-WindowLayout
        })
    }
    $script:LayoutTimer.Stop()
    $script:LayoutTimer.Start()
}

function Update-WindowLayout {
    if (-not $script:MainForm -or $script:MainForm.IsDisposed) { return }
    $w = [Math]::Max(0, $script:MainForm.ClientSize.Width)

    if ($script:HeaderActions) {
        $compact = $w -lt 900
        $showShorts = [bool]$script:PlayerEmbedded -and -not $compact
        if ($script:VideoOnlyBtn) { $script:VideoOnlyBtn.Visible = $showShorts }
        if ($script:ListToggleBtn) { $script:ListToggleBtn.Visible = $showShorts }
        $hideFav = $false
        $need = Get-HeaderActionsWidth -ShowShorts $showShorts -HideFav $false
        if ($need -gt [Math]::Max(150, $w - 186)) {
            $hideFav = $true
            $need = Get-HeaderActionsWidth -ShowShorts $showShorts -HideFav $true
        }
        if ($script:FavFilterBtn) { $script:FavFilterBtn.Visible = -not $hideFav }
        $script:HeaderActions.Width = [Math]::Min(516, [Math]::Max(120, $need))
    }
    Update-ToolbarLayout
    if ($script:FooterHint) {
        $hintText = if ($w -lt 600) { 'Clic para desplegar y reproducir' }
            elseif ($w -lt 820) { 'Clic para desplegar  ·  Clic en una opción para verla' }
            else { 'Clic en una entrada para desplegarla  ·  Clic en una opción para verla aquí' }
        if ($script:FooterHint.Text -ne $hintText) { $script:FooterHint.Text = $hintText }
    }
    if (-not $script:SplitDrag -and -not $script:VideoOnly) { Set-SplitRatio $script:SplitRatio }
    Update-CardSizes
}

function Build-List {
    param([switch]$Force)

    if (-not $script:ListFlow) { return }
    $sig = Get-ListSignature
    if (-not $Force -and $sig -eq $script:ListSignature) { return }
    $script:ListBuildCount++

    $flow = $script:ListFlow
    $scrollY = 0
    try { $scrollY = [Math]::Abs($flow.AutoScrollPosition.Y) } catch { }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Cache de tarjetas: cada entrada se construye una sola vez. Buscar,
    # filtrar o marcar favoritos reordena controles existentes en lugar de
    # recrear cientos de ellos (era el coste de ~6 s por refresco).
    $catSig = Get-CatalogFingerprint
    if ($catSig -ne $script:CardCacheCatalog) {
        foreach ($k in @($script:CardCache.Keys)) {
            try { $script:CardCache[$k].Card.Dispose() } catch { }
        }
        $script:CardCache = @{}
        $script:CardCacheCatalog = $catSig
    }

    $visible = @(Get-VisiblePosts)

    $flow.SuspendLayout()
    try {
        # Las tarjetas que dejan de verse se desenganchan pero siguen en cache.
        for ($i = $flow.Controls.Count - 1; $i -ge 0; $i--) {
            $ctrl = $flow.Controls[$i]
            if (-not ($ctrl.Tag -and $ctrl.Tag.id)) { $ctrl.Dispose() }
            $flow.Controls.RemoveAt($i)
        }

        $script:Cards = New-Object System.Collections.ArrayList
        $script:CardById = @{}

        if ($visible.Count -eq 0) {
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.AutoSize = $false
            $lbl.TextAlign = 'MiddleCenter'
            $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
            $lbl.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 145)
            if ($script:SearchQuery) { $lbl.Text = "Sin resultados para «$($script:SearchBox.Text)»" }
            else { $lbl.Text = 'No hay entradas todavía. Pulsa "Actualizar".' }
            $lbl.Size = New-Object System.Drawing.Size([Math]::Max(280, $flow.ClientSize.Width - 40), 110)
            $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 30, 0, 0)
            [void]$flow.Controls.Add($lbl)
        }
        else {
            foreach ($p in $visible) {
                $id = [string]$p.id
                $c = $script:CardCache[$id]
                if ($c -and ($c.Card.IsDisposed -or [string]$c.Title -ne [string]$p.title)) {
                    try { $c.Card.Dispose() } catch { }
                    $c = $null
                }
                if (-not $c) {
                    $c = New-Card -Post $p
                    $script:CardCache[$id] = $c
                }
                [void]$script:Cards.Add($c)
                $script:CardById[$id] = $c
                [void]$flow.Controls.Add($c.Card)
                Update-Card $c
            }
            # La primera vez se abre la entrada mas reciente.
            if (-not $script:HasBuiltOnce) {
                $script:ExpandedId = $script:Cards[0].Id
                Update-Card $script:Cards[0]
                $script:HasBuiltOnce = $true
            }
        }
        # Poda: las entradas que ya no existen en la cache de datos liberan sus
        # controles para no acumular memoria entre scrapeos.
        if ($script:CardCache.Count -gt $script:Cards.Count) {
            $alive = @{}
            foreach ($p in $script:Posts) { $alive[[string]$p.id] = $true }
            foreach ($k in @($script:CardCache.Keys)) {
                if (-not $alive.ContainsKey([string]$k)) {
                    try { $script:CardCache[$k].Card.Dispose() } catch { }
                    $script:CardCache.Remove($k)
                }
            }
        }

        Update-CardSizes
        Update-StatusCounts
    }
    finally {
        $flow.ResumeLayout()
        # Mantiene la posicion de lectura tras un refresco (favoritos, busqueda
        # o catalogo) en lugar de saltar al principio.
        try {
            if ($scrollY -gt 0) {
                $flow.AutoScrollPosition = New-Object System.Drawing.Point(0, $scrollY)
            }
        } catch { }
        $script:ListSignature = $sig
        Write-Log ("Lista: {0} tarjetas en {1} ms" -f $script:Cards.Count, $sw.ElapsedMilliseconds)
    }
}

# --- Sugerencias del buscador --------------------------------------------
# Panel flotante sin activacion (WS_EX_NOACTIVATE): el cuadro de busqueda
# conserva el foco mientras se elige una consulta o se borra del historial.
function Hide-SearchHistory {
    # Cerrar el panel mientras WinForms lo esta mostrando deja un objeto
    # desechado y una excepcion modal: se aplaza al final de Show-SearchHistory.
    if ($script:SearchHistoryShowing) {
        $script:SearchHistoryHidePending = $true
        return
    }
    if ($script:SearchHistoryTimer) {
        try { $script:SearchHistoryTimer.Stop() } catch { }
        $script:SearchHistoryTimer = $null
    }
    if ($script:SearchHistoryForm -and -not $script:SearchHistoryForm.IsDisposed) {
        try { $script:SearchHistoryForm.Close() } catch { }
    }
    $script:SearchHistoryForm = $null
}

function Show-SearchHistory {
    param([string]$Filter = '')

    if (-not $script:SearchBox -or -not $script:SearchWrap) { return }
    if (-not $script:MainForm -or -not $script:MainForm.Visible) { return }

    $items = @($script:SearchHistory)
    $needle = ConvertTo-SearchText $Filter
    if ($needle) {
        $items = @($items | Where-Object { (ConvertTo-SearchText $_) -like "*$needle*" })
    }
    if ($items.Count -eq 0) { Hide-SearchHistory; return }

    Hide-SearchHistory

    $accent = Get-NeonColor
    $f = New-Object F1.HintForm
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.BackColor = $accent
    $f.Padding = New-Object System.Windows.Forms.Padding(1)
    $w = [Math]::Max(240, $script:SearchWrap.Width)
    $rows = [Math]::Min(8, $items.Count)
    $h = 10 + ($rows * 28) + 30
    $f.Size = New-Object System.Drawing.Size($w, $h)
    $p = $script:SearchWrap.PointToScreen([System.Drawing.Point]::new(0, $script:SearchWrap.Height + 2))
    $f.Location = $p
    $script:SearchHistoryForm = $f

    $shell = New-Object System.Windows.Forms.Panel
    $shell.Dock = 'Fill'
    $shell.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)
    [void]$f.Controls.Add($shell)

    $list = New-Object System.Windows.Forms.FlowLayoutPanel
    $list.Dock = 'Fill'
    $list.FlowDirection = 'TopDown'
    $list.WrapContents = $false
    $list.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)
    $list.Padding = New-Object System.Windows.Forms.Padding(4, 6, 4, 0)
    [void]$shell.Controls.Add($list)

    $foot = New-Object System.Windows.Forms.Panel
    $foot.Dock = 'Bottom'
    $foot.Height = 26
    $foot.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
    [void]$shell.Controls.Add($foot)

    $clearHist = New-Object System.Windows.Forms.Label
    $clearHist.Text = 'Borrar historial'
    $clearHist.AutoSize = $false
    $clearHist.TextAlign = 'MiddleLeft'
    $clearHist.Font = [System.Drawing.Font]::new('Segoe UI', 7.8)
    $clearHist.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 166)
    $clearHist.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
    $clearHist.Location = [System.Drawing.Point]::new(10, 0)
    $clearHist.Size = [System.Drawing.Size]::new(140, 26)
    $clearHist.Cursor = [System.Windows.Forms.Cursors]::Hand
    $clearHist.Add_Click({
        $script:SearchHistory = @()
        Save-State
        Hide-SearchHistory
    })
    [void]$foot.Controls.Add($clearHist)

    $escLbl = New-Object System.Windows.Forms.Label
    $escLbl.Text = 'Esc para cerrar'
    $escLbl.AutoSize = $false
    $escLbl.TextAlign = 'MiddleRight'
    $escLbl.Font = [System.Drawing.Font]::new('Segoe UI', 7.4)
    $escLbl.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 126)
    $escLbl.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
    $escLbl.Size = [System.Drawing.Size]::new(110, 26)
    $escLbl.Location = [System.Drawing.Point]::new(($w - 122), 0)
    [void]$foot.Controls.Add($escLbl)

    foreach ($item in $items) {
        $row = New-Object System.Windows.Forms.Panel
        $row.Size = [System.Drawing.Size]::new(($w - 12), 26)
        $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
        $row.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)

        $pick = New-Object System.Windows.Forms.Button
        $pick.Text = "$([char]::ConvertFromUtf32(0x2315))   $item"
        $pick.FlatStyle = 'Flat'
        $pick.FlatAppearance.BorderSize = 0
        $pick.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
        $pick.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)
        $pick.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
        $pick.TextAlign = 'MiddleLeft'
        $pick.Padding = [System.Windows.Forms.Padding]::new(8, 0, 26, 0)
        $pick.Font = [System.Drawing.Font]::new('Segoe UI', 8.4)
        $pick.AutoEllipsis = $true
        $pick.Size = [System.Drawing.Size]::new(($w - 40), 26)
        $pick.Cursor = [System.Windows.Forms.Cursors]::Hand
        $pick.Tag = [string]$item
        $pick.Add_Click({
            $q = [string]$this.Tag
            if ($script:SearchBox) {
                $script:SearchBox.Text = $q
                $script:SearchBox.SelectionStart = $q.Length
                $script:SearchQuery = ConvertTo-SearchText $q
                Build-List
                Save-State
            }
            Hide-SearchHistory
        })

        $del = New-Object System.Windows.Forms.Label
        $del.Text = [char]::ConvertFromUtf32(0x2715)
        $del.AutoSize = $false
        $del.TextAlign = 'MiddleCenter'
        $del.Font = [System.Drawing.Font]::new('Segoe UI', 8)
        $del.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 126)
        $del.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)
        $del.Location = [System.Drawing.Point]::new(($w - 40), 0)
        $del.Size = [System.Drawing.Size]::new(24, 26)
        $del.Cursor = [System.Windows.Forms.Cursors]::Hand
        $del.Tag = [string]$item
        $del.Add_MouseEnter({ $this.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 235) })
        $del.Add_MouseLeave({ $this.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 126) })
        $del.Add_Click({
            Remove-SearchHistory ([string]$this.Tag)
            Show-SearchHistory -Filter ([string]$script:SearchBox.Text)
        })

        $row.Controls.Add($pick)
        $row.Controls.Add($del)
        [void]$list.Controls.Add($row)
    }

    $f.Add_FormClosed({
        if ($script:SearchHistoryForm -eq $this) { $script:SearchHistoryForm = $null }
    })
    $script:SearchHistoryShowing = $true
    try { $f.Show() }
    catch { Write-Log "Sugerencias: no se pudieron mostrar ($($_.Exception.Message))" }
    finally {
        $script:SearchHistoryShowing = $false
        if ($script:SearchHistoryHidePending) {
            $script:SearchHistoryHidePending = $false
            Hide-SearchHistory
        }
    }
}

# --- Ventana principal ----------------------------------------------------
function New-CaptionButton {
    param(
        [string]$Text,
        [int]$Width = 32,
        [string]$Tip = '',
        [bool]$Danger = $false
    )

    $hover = [System.Drawing.Color]::FromArgb(40, 40, 52)
    $down = [System.Drawing.Color]::FromArgb(52, 52, 68)
    if ($Danger) {
        $hover = [System.Drawing.Color]::FromArgb(196, 43, 28)
        $down = [System.Drawing.Color]::FromArgb(150, 20, 10)
    }

    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $hover
    $b.FlatAppearance.MouseDownBackColor = $down
    $b.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 26)
    $b.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 232)
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $b.Size = New-Object System.Drawing.Size($Width, 30)
    $b.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.TabStop = $false
    if ($Tip -and $script:Tip) { $script:Tip.SetToolTip($b, $Tip) }
    return $b
}

function Update-WindowChrome {
    if (-not $script:MaxBtn) { return }
    if ($script:MainForm -and $script:MainForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized) {
        $script:MaxBtn.Text = [char]0x2750
    }
    else {
        $script:MaxBtn.Text = [char]0x25A1
    }
}

# --- Ventana principal ----------------------------------------------------
function Hide-MainWindow {
    if ($script:MainForm -and -not $script:MainForm.IsDisposed) { $script:MainForm.Hide() }
}

# Clic en el icono de la bandeja: muestra si esta oculta o minimizada; oculta si
# ya esta visible. Es el comportamiento clasico de una app de bandeja.
function Toggle-MainWindow {
    if (-not $script:MainForm -or $script:MainForm.IsDisposed) { Show-MainWindow; return }
    if ($script:MainForm.Visible -and $script:MainForm.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
        Hide-MainWindow
    }
    else {
        Show-MainWindow
    }
}

function Show-MainWindow {
    param([switch]$Hidden)

    if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
        $script:MainForm.Show()
        if ($script:MainForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $script:MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        Build-List
        $script:MainForm.Activate()
        $script:MainForm.BringToFront()
        if ($script:WindowLayer -ne 'normal') { Set-WindowLayer -Mode $script:WindowLayer }
        return
    }

    # Ventana propia sin bordes: el marco lo dibuja la app y el redimensionado
    # se resuelve con WM_NCHITTEST (F1.ShellForm).
    $form = New-Object F1.ShellForm
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.Text = 'F1 Tray Monitor'
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $winW = [Math]::Min(1180, [Math]::Max(860, $wa.Width - 80))
    $winH = [Math]::Min(900, [Math]::Max(560, $wa.Height - 80))
    $form.Size = New-Object System.Drawing.Size($winW, $winH)
    # Limite bajo a proposito: el diseno se adapta y el divisor ya no impone
    # anchos minimos, asi que la ventana puede hacerse pequena de verdad.
    $form.MinimumSize = New-Object System.Drawing.Size(520, 400)
    $form.StartPosition = 'Manual'
    $form.Location = [System.Drawing.Point]::new(
        ($wa.Left + [int](($wa.Width - $winW) / 2)),
        ($wa.Top + [int](($wa.Height - $winH) / 2))
    )
    $form.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 20)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 235)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.ShowInTaskbar = $true
    # Margen interior: deja visible el marco de 6 px que usa WM_NCHITTEST.
    $form.Padding = New-Object System.Windows.Forms.Padding(6)
    if ($script:AppIcon) { $form.Icon = $script:AppIcon }

    # --- Cabecera propia ---------------------------------------------------
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Fill'
    $header.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 26)

    $accent = New-Object System.Windows.Forms.Panel
    $accent.Dock = 'Left'
    $accent.Width = 5
    $accent.BackColor = [System.Drawing.Color]::FromArgb(225, 6, 0)
    $script:AccentPanel = $accent
    [void]$header.Controls.Add($accent)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = 'F1 TRAY MONITOR'
    $titleLbl.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $titleLbl.ForeColor = [System.Drawing.Color]::White
    $titleLbl.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 26)
    $titleLbl.AutoSize = $true
    $titleLbl.Location = New-Object System.Drawing.Point(18, 10)
    [void]$header.Controls.Add($titleLbl)

    $script:StatusLbl = New-Object System.Windows.Forms.Label
    $script:StatusLbl.Text = 'Cargando...'
    $script:StatusLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $script:StatusLbl.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 160)
    $script:StatusLbl.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 26)
    $script:StatusLbl.AutoSize = $true
    $script:StatusLbl.Location = New-Object System.Drawing.Point(20, 38)
    [void]$header.Controls.Add($script:StatusLbl)

    $headerRight = New-Object System.Windows.Forms.FlowLayoutPanel
    $headerRight.Dock = 'Right'
    $headerRight.Width = 516
    $headerRight.FlowDirection = 'RightToLeft'
    $headerRight.WrapContents = $false
    $headerRight.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 26)
    $headerRight.Padding = New-Object System.Windows.Forms.Padding(0, 17, 8, 0)
    [void]$header.Controls.Add($headerRight)
    $script:HeaderActions = $headerRight

    $closeBtn = New-CaptionButton -Text ([char]0x2715) -Tip 'Cerrar (la app sigue en la bandeja)' -Danger $true
    $closeBtn.Add_Click({ if ($script:MainForm) { $script:MainForm.Hide() } })
    [void]$headerRight.Controls.Add($closeBtn)

    $script:MaxBtn = New-CaptionButton -Text ([char]0x25A1) -Tip 'Maximizar / restaurar'
    $script:MaxBtn.Add_Click({ Toggle-Maximize })
    [void]$headerRight.Controls.Add($script:MaxBtn)

    $minBtn = New-CaptionButton -Text ([char]0x2212) -Tip 'Minimizar'
    $minBtn.Add_Click({
        if ($script:MainForm) { $script:MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized }
    })
    [void]$headerRight.Controls.Add($minBtn)

    $script:VideoOnlyBtn = New-CaptionButton -Text 'Solo vídeo' -Width 104 -Tip 'Ocultar todo menos el vídeo'
    $script:VideoOnlyBtn.Enabled = $false
    $script:VideoOnlyBtn.Add_Click({ Set-VideoOnly -Enabled $true })
    [void]$headerRight.Controls.Add($script:VideoOnlyBtn)

    $script:ListToggleBtn = New-CaptionButton -Text 'Ocultar lista' -Width 118 -Tip 'Mostrar u ocultar el listado de entradas'
    $script:ListToggleBtn.Add_Click({ Set-ListVisible -Visible (-not $script:ListVisible) })
    [void]$headerRight.Controls.Add($script:ListToggleBtn)

    $refreshBtn = New-CaptionButton -Text 'Actualizar' -Width 96 -Tip 'Buscar nuevas entradas ahora'
    $refreshBtn.BackColor = [System.Drawing.Color]::FromArgb(225, 6, 0)
    $refreshBtn.ForeColor = [System.Drawing.Color]::White
    $refreshBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(255, 40, 30)
    $refreshBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $refreshBtn.Add_Click({ Start-Scrape })
    [void]$headerRight.Controls.Add($refreshBtn)
    $script:RefreshBtn = $refreshBtn

    $script:FavFilterBtn = New-CaptionButton -Text ([char]0x2606) -Tip 'Mostrar solo favoritos'
    $script:FavFilterBtn.Font = [System.Drawing.Font]::new('Segoe UI Symbol', 12)
    $script:FavFilterBtn.Add_Click({
        $script:FavoritesOnly = -not $script:FavoritesOnly
        Update-FavoriteFilterButton
        Build-List
        Write-Log "Filtro de favoritos: $($script:FavoritesOnly)"
    })
    [void]$headerRight.Controls.Add($script:FavFilterBtn)
    Update-FavoriteFilterButton

    $dragHandler = {
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $script:MainForm) {
            [F1.Native]::Drag($script:MainForm.Handle)
        }
    }
    $header.Add_MouseDown($dragHandler)
    $accent.Add_MouseDown($dragHandler)
    $titleLbl.Add_MouseDown($dragHandler)
    $script:StatusLbl.Add_MouseDown($dragHandler)
    $header.Add_DoubleClick({ Toggle-Maximize })
    $titleLbl.Add_DoubleClick({ Toggle-Maximize })

    # --- Barra de herramientas: buscador + pagina siguiente ---------------
    $toolbar = New-Object System.Windows.Forms.Panel
    $toolbar.Dock = 'Fill'
    $toolbar.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 23)

    $searchWrap = New-Object System.Windows.Forms.Panel
    $searchWrap.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 33)
    $searchWrap.Location = New-Object System.Drawing.Point(12, 7)
    $searchWrap.Size = New-Object System.Drawing.Size(420, 30)
    $searchWrap.Anchor = 'Top,Left,Right'
    [void]$toolbar.Controls.Add($searchWrap)
    $script:SearchWrap = $searchWrap

    $searchIcon = New-Object System.Windows.Forms.Label
    $searchIcon.Text = [char]::ConvertFromUtf32(0x2315)
    $searchIcon.Dock = 'Left'
    $searchIcon.Width = 28
    $searchIcon.TextAlign = 'MiddleCenter'
    $searchIcon.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $searchIcon.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 138)
    [void]$searchWrap.Controls.Add($searchIcon)

    $clearBtn = New-Object System.Windows.Forms.Button
    $clearBtn.Text = [char]::ConvertFromUtf32(0x00D7)
    $clearBtn.Dock = 'Right'
    $clearBtn.Width = 26
    $clearBtn.FlatStyle = 'Flat'
    $clearBtn.FlatAppearance.BorderSize = 0
    $clearBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(45, 45, 58)
    $clearBtn.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 33)
    $clearBtn.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 165)
    $clearBtn.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $clearBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $clearBtn.TabStop = $false
    [void]$searchWrap.Controls.Add($clearBtn)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.BorderStyle = 'None'
    $searchBox.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 33)
    $searchBox.ForeColor = [System.Drawing.Color]::FromArgb(236, 236, 243)
    $searchBox.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $searchBox.Location = New-Object System.Drawing.Point(30, 6)
    $searchBox.Size = New-Object System.Drawing.Size(360, 20)
    $searchBox.Anchor = 'Top,Left,Right'
    $searchBox.Add_HandleCreated({
        try {
            [void][F1.Ui]::SendMessage($this.Handle, 0x1501, [IntPtr]1, 'Buscar GP, sesión u opción...')
        } catch { }
    })
    [void]$searchWrap.Controls.Add($searchBox)
    $script:SearchBox = $searchBox

    $script:SearchTimer = New-Object System.Windows.Forms.Timer
    $script:SearchTimer.Interval = 180
    $script:SearchTimer.Add_Tick({
        $script:SearchTimer.Stop()
        $script:SearchQuery = ConvertTo-SearchText $script:SearchBox.Text
        Build-List
        Save-State
    })
    $searchBox.Add_TextChanged({
        $script:SearchTimer.Stop()
        $script:SearchTimer.Start()
        if ($script:SearchHistoryForm) { Show-SearchHistory -Filter $script:SearchBox.Text }
    })
    $searchBox.Add_GotFocus({
        if (@($script:SearchHistory).Count -gt 0) { Show-SearchHistory -Filter $script:SearchBox.Text }
    })
    $searchBox.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            Add-SearchHistory ([string]$script:SearchBox.Text)
            Hide-SearchHistory
        }
        elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            Hide-SearchHistory
        }
    })
    $searchBox.Add_Leave({ Hide-SearchHistory })
    $clearBtn.Add_Click({
        $script:SearchBox.Clear()
        $script:SearchQuery = ''
        Build-List
        Save-State
        $script:SearchBox.Focus() | Out-Null
        Hide-SearchHistory
    })

    # Restaura el ultimo filtro si el ajuste "Recordar busqueda" esta activo.
    if ($script:Config.rememberSearch -and $script:SavedSearch) {
        $searchBox.Text = $script:SavedSearch
    }

    $script:NextPageBtn = New-Object System.Windows.Forms.Button
    $script:NextPageBtn.Text = 'Cargar página 2'
    $script:NextPageBtn.FlatStyle = 'Flat'
    $script:NextPageBtn.FlatAppearance.BorderSize = 1
    $script:NextPageBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64, 64, 80)
    $script:NextPageBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 34, 46)
    $script:NextPageBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
    $script:NextPageBtn.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 238)
    $script:NextPageBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $script:NextPageBtn.Size = New-Object System.Drawing.Size(148, 30)
    $script:NextPageBtn.Location = New-Object System.Drawing.Point(560, 7)
    $script:NextPageBtn.Anchor = 'Top,Right'
    $script:NextPageBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $script:NextPageBtn.Add_Click({ Start-PageLoad })
    [void]$toolbar.Controls.Add($script:NextPageBtn)

    $script:LoadAllBtn = New-Object System.Windows.Forms.Button
    $script:LoadAllBtn.Text = 'Cargar todo'
    $script:LoadAllBtn.FlatStyle = 'Flat'
    $script:LoadAllBtn.FlatAppearance.BorderSize = 1
    $script:LoadAllBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(225, 6, 0)
    $script:LoadAllBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(60, 12, 12)
    $script:LoadAllBtn.BackColor = [System.Drawing.Color]::FromArgb(34, 14, 16)
    $script:LoadAllBtn.ForeColor = [System.Drawing.Color]::FromArgb(255, 214, 210)
    $script:LoadAllBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $script:LoadAllBtn.Size = New-Object System.Drawing.Size(118, 30)
    $script:LoadAllBtn.Location = New-Object System.Drawing.Point(434, 7)
    $script:LoadAllBtn.Anchor = 'Top,Right'
    $script:LoadAllBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $script:LoadAllBtn.Add_Click({ Toggle-LoadAllPages })
    [void]$toolbar.Controls.Add($script:LoadAllBtn)

    $toolbar.Add_Resize({ Update-ToolbarLayout })

    # --- Contenido: listado a la izquierda, video a la derecha -------------
    $contentHost = New-Object System.Windows.Forms.Panel
    $contentHost.Dock = 'Fill'
    $contentHost.BackColor = [System.Drawing.Color]::FromArgb(9, 9, 13)

    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'
    $split.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $split.SplitterWidth = 6
    $split.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 38)
    $split.Panel1.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 20)
    $split.Panel2.BackColor = [System.Drawing.Color]::FromArgb(5, 5, 10)
    [void]$contentHost.Controls.Add($split)

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'
    $flow.FlowDirection = 'TopDown'
    $flow.WrapContents = $false
    $flow.AutoScroll = $true
    $flow.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 20)
    $flow.Padding = [System.Windows.Forms.Padding]::new(10, 8, 10, 8)
    $flow.Add_Resize({ Request-Layout })
    [void]$split.Panel1.Controls.Add($flow)
    $script:ListFlow = $flow
    Enable-DarkScrollbars $flow

    $videoHost = New-Object System.Windows.Forms.Panel
    $videoHost.Dock = 'Fill'
    $videoHost.BackColor = [System.Drawing.Color]::FromArgb(5, 5, 10)
    [void]$split.Panel2.Controls.Add($videoHost)

    $videoPlaceholder = New-Object System.Windows.Forms.Label
    $videoPlaceholder.Dock = 'Fill'
    $videoPlaceholder.TextAlign = 'MiddleCenter'
    $videoPlaceholder.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $videoPlaceholder.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 138)
    $videoPlaceholder.Text = "Selecciona una opción del listado`r`npara reproducir aquí"
    [void]$videoHost.Controls.Add($videoPlaceholder)
    $script:VideoPlaceholder = $videoPlaceholder

    $embedded = $false
    if ($script:Config.playerMode -ne 'external' -and (Initialize-WebView2)) {
        $wv = New-EmbeddedWebView -HostPanel $videoHost
        $embedded = ($null -ne $wv)
    }
    if (-not $embedded) { $split.Panel2Collapsed = $true }

    $script:VideoOnlyBtn.Visible = $embedded
    $script:ListToggleBtn.Visible = $embedded
    $script:PlayerEmbedded = $embedded
    $script:Split = $split

    # Arrastrar el divisor guarda la proporcion; cerca del borde izquierdo el
    # listado se oculta en lugar de quedarse en una franja inservible.
    $split.Add_SplitterMoved({
        param($sender, $e)
        if ($script:SplitDrag) { return }
        # Redimensionar la ventana (o recolocar el divisor por codigo) tambien
        # dispara este evento. Solo es un arrastre real si el boton izquierdo
        # sigue pulsado; asi la proporcion guardada no se desvia sola.
        if ([System.Windows.Forms.Control]::MouseButtons -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        if ($script:SplitTarget -gt 0 -and [Math]::Abs($sender.SplitterDistance - $script:SplitTarget) -lt 2) { return }
        $script:SplitTarget = $sender.SplitterDistance
        $total = $sender.Width - $sender.SplitterWidth
        if ($total -lt 140) { return }
        $ratio = [double]$sender.SplitterDistance / $total
        if ($ratio -lt 0.12) {
            Set-ListVisible -Visible $false
            return
        }
        $script:SplitRatio = [Math]::Max(0.10, [Math]::Min(0.90, $ratio))
        if (-not $script:StateSaveTimer) {
            $script:StateSaveTimer = New-Object System.Windows.Forms.Timer
            $script:StateSaveTimer.Interval = 800
            $script:StateSaveTimer.Add_Tick({
                $script:StateSaveTimer.Stop()
                Save-State
            })
        }
        $script:StateSaveTimer.Stop()
        $script:StateSaveTimer.Start()
    })
    $split.Add_DoubleClick({ Set-SplitRatio 0.42 })
    $script:VideoHost = $videoHost
    $script:Toolbar = $toolbar
    $script:Header = $header

    # --- Pie ---------------------------------------------------------------
    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Fill'
    $footer.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)

    $footerLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $footerLayout.Dock = 'Fill'
    $footerLayout.ColumnCount = 2
    $footerLayout.RowCount = 1
    [void]$footerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$footerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 170)))
    [void]$footer.Controls.Add($footerLayout)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Clic en una entrada para desplegarla  ·  Clic en una opción para verla aquí'
    $hint.Dock = 'Fill'
    $hint.TextAlign = 'MiddleLeft'
    $hint.AutoEllipsis = $true
    $hint.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 125)
    [void]$footerLayout.Controls.Add($hint, 0, 0)
    $script:FooterHint = $hint

    $script:CountLbl = New-Object System.Windows.Forms.Label
    $script:CountLbl.Text = "$($script:Posts.Count) entradas"
    $script:CountLbl.Dock = 'Fill'
    $script:CountLbl.TextAlign = 'MiddleRight'
    $script:CountLbl.AutoEllipsis = $true
    $script:CountLbl.Padding = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
    $script:CountLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $script:CountLbl.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 145)
    [void]$footerLayout.Controls.Add($script:CountLbl, 1, 0)
    $script:Footer = $footer

    # --- Distribucion ------------------------------------------------------
    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 4
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 64)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 26)))
    [void]$form.Controls.Add($layout)
    [void]$layout.Controls.Add($header, 0, 0)
    [void]$layout.Controls.Add($toolbar, 0, 1)
    [void]$layout.Controls.Add($contentHost, 0, 2)
    [void]$layout.Controls.Add($footer, 0, 3)
    $script:Layout = $layout

    $form.Add_FormClosing({
        param($sender, $e)
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $e.Cancel = $true
            $sender.Hide()
        }
    })
    $form.Add_Resize({
        param($sender, $e)
        Update-WindowChrome
        if ($sender.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) { Request-Layout }
    })
    $form.Add_Shown({
        if ($script:Split -and -not $script:Split.Panel2Collapsed) {
            try {
                # Sin minimos fijos: el divisor se mueve con la proporcion
                # guardada y puede llegar casi a los bordes.
                $script:Split.Panel1MinSize = 1
                $script:Split.Panel2MinSize = 1
                Set-SplitRatio $script:SplitRatio
            } catch { }
        }
        Update-ToolbarLayout
        Update-WindowLayout
    })
    $form.Add_Deactivate({ Hide-SearchHistory })

    $script:MainForm = $form
    $swCreate = [System.Diagnostics.Stopwatch]::StartNew()
    Build-List
    Update-PageButton
    if ($script:StatusLbl -and $script:StatusLbl.Text -eq 'Cargando...') {
        $script:StatusLbl.Text = "$($script:Posts.Count) entradas en caché"
    }
    Write-Log ("Ventana: creada en {0} ms ({1} tarjetas)" -f $swCreate.ElapsedMilliseconds, $script:Cards.Count)

    if ($Hidden) {
        # Precalentado sin parpadeo: se crea, se maqueta y se oculta. El primer
        # clic en la bandeja solo tiene que mostrarla.
        $form.ShowInTaskbar = $false
        $form.Opacity = 0
        $form.Show()
        $form.Hide()
        $form.Opacity = 1
        $form.ShowInTaskbar = $true
        $script:WindowPrewarm = $true
        Write-Log 'Prewarm: ventana oculta lista'
        return
    }

    $form.Show()
    try {
        [void][F1.User32]::ShowWindow($form.Handle, 5)   # SW_SHOW
        [void][F1.User32]::SetForegroundWindow($form.Handle)
    } catch { }
    $form.Activate()
    $form.BringToFront()
    if ($script:WindowLayer -ne 'normal') { Set-WindowLayer -Mode $script:WindowLayer }
    Update-CardSizes
    Update-WindowChrome
    Apply-NeonToWindow
    try {
        Write-Log ("Ventana: bounds=$($form.Bounds) client=$($form.ClientSize) wa=$wa dpi=$($form.DeviceDpi) embedded=$embedded")
    } catch { }
}
# --- Scraper en segundo plano ---------------------------------------------
# Se lanza como proceso independiente y se vigila con un temporizador de la UI.
# Evita los manejadores de eventos en hilos de fondo, que en PowerShell 5.1
# pueden perder el contexto del script.
function Complete-Scrape {
    $proc = $script:ScrapeProc
    if (-not $proc) {
        if ($script:ScrapeTimer) { $script:ScrapeTimer.Stop() }
        return
    }
    $exited = $false
    try { $exited = $proc.HasExited } catch { $exited = $true }
    if (-not $exited) { return }

    if ($script:ScrapeTimer) { $script:ScrapeTimer.Stop() }
    $exit = -1
    try { [void]$proc.WaitForExit(); $exit = [int]$proc.ExitCode } catch { }
    $script:ScrapeProc = $null
    $script:IsScraping = $false

    $secs = 0
    if ($script:ScrapeStarted) { $secs = [Math]::Round(((Get-Date) - $script:ScrapeStarted).TotalSeconds, 1) }
    if ($exit -ne 0) { Write-Log "Scraper termino con codigo $exit tras ${secs}s" }
    else { Write-Log "Scraper completado en ${secs}s" }
    try {
        if ($script:ScrapeErrFile -and (Test-Path $script:ScrapeErrFile)) {
            $errText = ([System.IO.File]::ReadAllText($script:ScrapeErrFile, [System.Text.Encoding]::Default)).Trim()
            if ($errText) { Write-Log "Scraper stderr: $errText" }
        }
        if ($script:ScrapeOutFile -and (Test-Path $script:ScrapeOutFile)) {
            $outText = [System.IO.File]::ReadAllText($script:ScrapeOutFile, [System.Text.Encoding]::Default)
            $outLines = @($outText -split "`r?`n" | Where-Object { $_.Trim() })
            if ($outLines.Count -gt 0) { Write-Log ("Scraper salida: " + $outLines[-1]) }
        }
    } catch { }
    try {
        if ($script:ScrapeOutFile -and (Test-Path $script:ScrapeOutFile)) { Remove-Item $script:ScrapeOutFile -Force -ErrorAction SilentlyContinue }
        if ($script:ScrapeErrFile -and (Test-Path $script:ScrapeErrFile)) { Remove-Item $script:ScrapeErrFile -Force -ErrorAction SilentlyContinue }
    } catch { }

    $posts = Load-Posts
    $script:Posts = $posts

    $newOnes = @()
    foreach ($p in $posts) {
        $id = [string]$p.id
        if ($id -and -not $script:KnownIds.Contains($id)) {
            [void]$script:KnownIds.Add($id)
            if ($script:FirstSeed) { $newOnes += $p }
        }
    }

    if (-not $script:FirstSeed) {
        $script:FirstSeed = $true
        Write-Log "Primera carga: $($posts.Count) entradas en caché"
        Show-Balloon 'F1 Tray Monitor' "Monitor listo. $($posts.Count) entradas en caché." 'Info'
    }
    elseif ($newOnes.Count -gt 0) {
        foreach ($p in $newOnes) {
            Write-Log "NUEVA: [$($p.type)] $($p.title)"
        }
        # Un solo aviso por comprobacion: si el scraper encuentra varias
        # entradas, Windows no debe lanzar una lluvia de globos a la vez.
        if ($newOnes.Count -eq 1) {
            Show-Balloon "Nueva entrada F1 - $($newOnes[0].type)" (Get-ShortTitle $newOnes[0].title) 'Info'
        }
        else {
            $first = Get-ShortTitle $newOnes[0].title
            Show-Balloon "Nuevas entradas F1 ($($newOnes.Count))" "$first y $($newOnes.Count - 1) mas." 'Info'
        }
    }
    else {
        Write-Log "Sin entradas nuevas. Cache: $($posts.Count) entradas"
    }

    Build-SearchIndex
    Refresh-Menu
    if ($script:MainForm -and -not $script:MainForm.IsDisposed -and $script:MainForm.Visible) {
        Build-List
    }
    Update-StatusCounts
    if ($script:StatusLbl) {
        $script:StatusLbl.Text = "Actualizado $(Get-Date -Format 'HH:mm')  -  $($posts.Count) entradas"
    }

    # Ajuste "Cargar todo al iniciar": tras el primer scrapeo encadena paginas.
    if ($script:Config.autoLoadAll -and -not $script:AutoLoadDone -and -not $SelfTest) {
        $script:AutoLoadDone = $true
        Write-Log 'Ajuste: cargar todo al iniciar'
        Toggle-LoadAllPages
    }
}

function Start-Scrape {
    if ($script:IsScraping) { return }
    if ($script:IsPaging) { Write-Log 'Scraping omitido: paginacion en curso'; return }
    if (-not (Test-Path $scraperFile)) {
        Write-Log "No existe el scraper: $scraperFile"
        return
    }

    $script:IsScraping = $true
    $script:ScrapeStarted = Get-Date
    if ($script:StatusLbl) { $script:StatusLbl.Text = 'Comprobando nuevas entradas...' }
    Write-Log 'Iniciando scraping...'

    $script:ScrapeOutFile = Join-Path $env:TEMP ("f1-scrape-{0}.log" -f [guid]::NewGuid().ToString('N'))
    $script:ScrapeErrFile = "$($script:ScrapeOutFile).err"

    try {
        $psArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scraperFile,
                    '-DataDir', $scriptDir, '-MaxPosts', [string]$script:Config.maxPostsOnFirstRun)
        $script:ScrapeProc = Start-Process -FilePath $psExe -ArgumentList $psArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $script:ScrapeOutFile -RedirectStandardError $script:ScrapeErrFile
    } catch {
        Write-Log "Scraper: no se pudo lanzar: $_"
        $script:ScrapeProc = $null
        $script:IsScraping = $false
        if ($script:StatusLbl) { $script:StatusLbl.Text = 'Error al iniciar la comprobación' }
        return
    }

    if (-not $script:ScrapeTimer) {
        $script:ScrapeTimer = New-Object System.Windows.Forms.Timer
        $script:ScrapeTimer.Interval = 800
        $script:ScrapeTimer.Add_Tick({ Complete-Scrape })
    }
    $script:ScrapeTimer.Start()
}

# --- Paginacion del blog --------------------------------------------------
function Update-PageButton {
    if (-not $script:NextPageBtn) { return }

    if ($script:LoadAllBtn) {
        if ($script:LoadAll) {
            $script:LoadAllBtn.Text = 'Detener'
            $script:LoadAllBtn.Enabled = $true
        }
        elseif ($script:NoMorePages) {
            $script:LoadAllBtn.Text = 'Todo cargado'
            $script:LoadAllBtn.Enabled = $false
        }
        else {
            $script:LoadAllBtn.Text = 'Cargar todo'
            $script:LoadAllBtn.Enabled = $true
        }
    }

    if ($script:IsPaging) {
        $script:NextPageBtn.Enabled = $false
        if ($script:LoadAll) { $script:NextPageBtn.Text = "Cargando todo... ($($script:NextPage))" }
        else { $script:NextPageBtn.Text = 'Cargando...' }
        return
    }
    if ($script:NoMorePages) {
        $script:NextPageBtn.Enabled = $false
        $script:NextPageBtn.Text = 'No hay más páginas'
        return
    }
    $script:NextPageBtn.Enabled = $true
    $script:NextPageBtn.Text = "Cargar página $($script:NextPage)"
}

# --- Carga por lotes (mucho mas rapida) -----------------------------------
# Un unico proceso recorre varias paginas y descarga las fichas en paralelo.
# La ventana lee el archivo de progreso para mostrar avances sin bloquearse.

function Sync-KnownIds {
    foreach ($p in $script:Posts) {
        if ($p.id) { [void]$script:KnownIds.Add([string]$p.id) }
    }
}

function Read-LoadProgress {
    if (-not (Test-Path $script:LoadAllProgressFile)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($script:LoadAllProgressFile, [System.Text.Encoding]::UTF8)
        if (-not $raw -or -not $raw.Trim()) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch { return $null }
}

function Update-LoadProgressUi {
    $p = Read-LoadProgress
    if (-not $p) { return }

    $phase = [string]$p.phase
    if ($phase -eq 'pages') {
        if ($script:NextPageBtn) { $script:NextPageBtn.Text = "Cargando todo... ($($p.page))" }
        if ($script:StatusLbl) { $script:StatusLbl.Text = "Cargando pagina $($p.page)  -  $($p.added) nuevas" }
    }
    elseif ($phase -eq 'details') {
        $d = if ($null -ne $p.done) { [int]$p.done } else { 0 }
        $n = if ($null -ne $p.new_total) { [int]$p.new_total } else { 0 }
        if ($script:NextPageBtn) { $script:NextPageBtn.Text = "Cargando fuentes... ($d/$n)" }
        if ($script:StatusLbl) { $script:StatusLbl.Text = "Cargando fuentes $d/$n  -  $($p.added) nuevas" }
    }

    # Refrescar la lista cuando el lote ha escrito el cache (cada ~2 s), pero
    # como maximo una reconstruccion cada 4 s para no castigar la interfaz.
    $written = 0
    if ($null -ne $p.written) { $written = [int]$p.written }
    if ($written -ne $script:LoadAllWritten) {
        $now = Get-Date
        if (($now - $script:LoadAllUiAt).TotalSeconds -ge 4) {
            $script:LoadAllWritten = $written
            $script:LoadAllUiAt = $now
            $script:Posts = Load-Posts
            Sync-KnownIds
            Build-SearchIndex
            if ($script:MainForm -and -not $script:MainForm.IsDisposed -and $script:MainForm.Visible) {
                Build-List
            }
            Update-StatusCounts
        }
    }
}

# Carga todas las paginas del blog en un solo lote. Un segundo clic detiene.
function Toggle-LoadAllPages {
    if ($script:LoadAll) {
        $script:LoadAll = $false
        if ($script:LoadAllTimer) { $script:LoadAllTimer.Stop() }
        if ($script:PageTimer) { $script:PageTimer.Stop() }

        $killed = $false
        if ($script:PageProc) {
            try {
                if (-not $script:PageProc.HasExited) {
                    & taskkill.exe /PID $script:PageProc.Id /T /F 2>$null | Out-Null
                    $killed = $true
                }
            } catch { }
            $script:PageProc = $null
        }
        $script:IsPaging = $false

        $p = Read-LoadProgress
        if ($p) {
            if ($null -ne $p.last_page -and [int]$p.last_page -ge 2) {
                $script:NextPage = [Math]::Max(2, [int]$p.last_page + 1)
            }
            elseif ($null -ne $p.page -and [int]$p.page -ge 2) {
                $script:NextPage = [Math]::Max(2, [int]$p.page + 1)
            }
        }
        try {
            $stop = [ordered]@{
                active = $false; phase = 'stopped'
                last_page = [Math]::Max(1, [int]$script:NextPage - 1)
                updated = (Get-Date).ToString('o')
            }
            [System.IO.File]::WriteAllText(
                $script:LoadAllProgressFile,
                ($stop | ConvertTo-Json -Compress),
                (New-Object System.Text.UTF8Encoding($false)))
        } catch { }

        $script:Posts = Load-Posts
        Sync-KnownIds
        Build-SearchIndex
        Refresh-Menu
        if ($script:MainForm -and -not $script:MainForm.IsDisposed -and $script:MainForm.Visible) {
            Build-List
        }
        else { Update-StatusCounts }
        if ($script:StatusLbl) { $script:StatusLbl.Text = "Carga detenida  -  $($script:Posts.Count) entradas" }
        Save-State
        Write-Log "Cargar todo: detenido por el usuario (killed=$killed)"
        Update-PageButton
        return
    }
    if ($script:NoMorePages) { Update-PageButton; return }
    if ($script:IsScraping) { Write-Log 'Cargar todo: hay un scraping en curso'; return }
    if ($script:IsPaging) { Write-Log 'Cargar todo: ya hay una carga en curso'; return }

    $from = [Math]::Max(2, [int]$script:NextPage)
    $to = $from + [Math]::Max(1, [int]$script:LoadAllMax) - 1
    $script:LoadAll = $true
    $script:LoadAllPages = 0
    $script:AutoLoadDone = $true
    Write-Log "Cargar todo: paginas $from-$to en un solo lote paralelo"
    Start-BatchLoad -From $from -To $to
}

function Complete-PageLoad {
    $proc = $script:PageProc
    if (-not $proc) { if ($script:PageTimer) { $script:PageTimer.Stop() }; return }
    $exited = $false
    try { $exited = $proc.HasExited } catch { $exited = $true }
    if (-not $exited) { Update-LoadProgressUi; return }

    if ($script:PageTimer) { $script:PageTimer.Stop() }
    $exit = -1
    try { [void]$proc.WaitForExit(); $exit = [int]$proc.ExitCode } catch { }

    $from = [Math]::Max(2, [int]$script:LoadAllBatchFrom)
    $to = [Math]::Max($from, [int]$script:LoadAllBatchTo)
    Write-Log "Paginacion: scraper exit=$exit (paginas $from-$to)"

    $added = 0; $total = 0; $scanned = 0; $elapsed = 0
    $lastPage = $from - 1
    $emptyPage = 0
    $failedPage = 0
    $outFile = $script:PageOutFile
    $errFile = $script:PageErrFile
    $info = $null

    try {
        if ($outFile -and (Test-Path $outFile)) {
            $text = [System.IO.File]::ReadAllText($outFile, [System.Text.Encoding]::Default)
            $lines = @($text -split "`r?`n" | Where-Object { $_.Trim() })
            if ($lines.Count -gt 0) {
                try { $info = $lines[-1] | ConvertFrom-Json } catch { $info = $null }
                if ($info) {
                    if ($null -ne $info.added) { $added = [int]$info.added }
                    if ($null -ne $info.total_posts) { $total = [int]$info.total_posts }
                    if ($null -ne $info.last_page) { $lastPage = [int]$info.last_page }
                    if ($null -ne $info.empty_page) { $emptyPage = [int]$info.empty_page }
                    if ($null -ne $info.failed_page) { $failedPage = [int]$info.failed_page }
                    if ($null -ne $info.pages_scanned) { $scanned = [int]$info.pages_scanned }
                    if ($null -ne $info.elapsed_ms) { $elapsed = [int]$info.elapsed_ms }
                }
            }
            else { Write-Log 'Paginacion: salida vacia' }
        }
        if ($errFile -and (Test-Path $errFile)) {
            $errText = ([System.IO.File]::ReadAllText($errFile, [System.Text.Encoding]::Default)).Trim()
            if ($errText) { Write-Log "Paginacion stderr: $errText" }
        }
    } catch {
        Write-Log "Paginacion: no se pudo leer el resultado: $_"
    }
    try { if ($outFile) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue } } catch { }
    try { if ($errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue } } catch { }

    # Si el proceso no dejo resultado (por ejemplo, se cerro solo), el archivo
    # de progreso sigue teniendo la ultima pagina completada.
    if (-not $info) {
        $p = Read-LoadProgress
        if ($p) {
            if ($null -ne $p.last_page) { $lastPage = [int]$p.last_page }
            if ($null -ne $p.added) { $added = [int]$p.added }
            if ($null -ne $p.total) { $total = [int]$p.total }
            if ($null -ne $p.page -and $p.phase -eq 'pages') { $lastPage = [Math]::Max($lastPage, [int]$p.page) }
        }
    }

    if ($emptyPage -gt 0) {
        $script:NoMorePages = $true
        Write-Log "Paginacion: pagina $emptyPage vacia, no hay mas paginas"
    }
    if ($lastPage -ge $from) {
        $script:NextPage = [Math]::Max(2, $lastPage + 1)
        Save-State
    }

    $script:Posts = Load-Posts
    if ($total -le 0) { $total = $script:Posts.Count }
    Sync-KnownIds
    Build-SearchIndex
    Refresh-Menu
    if ($script:MainForm -and -not $script:MainForm.IsDisposed -and $script:MainForm.Visible) {
        Build-List
    }
    else { Update-StatusCounts }

    $script:PageProc = $null
    $script:IsPaging = $false
    Update-PageButton

    $pagesDone = [Math]::Max(0, $lastPage - $from + 1)
    Write-Log "Paginacion: $pagesDone paginas, $added nuevas, $total en cache, ${elapsed}ms"

    if ($script:LoadAll) {
        $script:LoadAll = $false
        if ($script:NoMorePages) {
            if ($script:StatusLbl) { $script:StatusLbl.Text = "Todo cargado  -  $($script:Posts.Count) entradas" }
            Write-Log "Cargar todo: completado con $($script:Posts.Count) entradas"
        }
        elseif ($failedPage -gt 0) {
            if ($script:StatusLbl) { $script:StatusLbl.Text = "Carga interrumpida en la pagina $failedPage  -  $($script:Posts.Count) entradas" }
            Write-Log "Cargar todo: fallo la pagina $failedPage"
        }
        elseif ($lastPage -ge $to) {
            if ($script:StatusLbl) { $script:StatusLbl.Text = "Limite de $($script:LoadAllMax) paginas alcanzado  -  $($script:Posts.Count) entradas" }
            Write-Log "Cargar todo: limite de $($script:LoadAllMax) paginas alcanzado"
        }
        else {
            if ($script:StatusLbl) { $script:StatusLbl.Text = "Todo cargado  -  $($script:Posts.Count) entradas" }
        }
        Update-PageButton
        return
    }

    if ($script:StatusLbl) {
        if ($emptyPage -gt 0) { $script:StatusLbl.Text = "No hay mas paginas  -  $($script:Posts.Count) entradas" }
        elseif ($failedPage -gt 0) { $script:StatusLbl.Text = "No se pudo cargar la pagina $failedPage" }
        elseif ($pagesDone -eq 1) { $script:StatusLbl.Text = "Pagina $lastPage cargada (+$added)  -  $($script:Posts.Count) entradas" }
        else { $script:StatusLbl.Text = "Paginas $from-$lastPage cargadas (+$added)  -  $($script:Posts.Count) entradas" }
    }
    Update-PageButton
}

function Start-BatchLoad {
    param([int]$From, [int]$To)

    if ($script:IsPaging) { return }
    if ($script:IsScraping) { Write-Log 'Paginacion omitida: scraping en curso'; return }
    if (-not (Test-Path $scraperFile)) {
        Write-Log "No existe el scraper: $scraperFile"
        return
    }

    $From = [Math]::Max(2, $From)
    $To = [Math]::Max($From, $To)
    $script:LoadAllBatchFrom = $From
    $script:LoadAllBatchTo = $To
    $script:PageRequest = $From
    $script:IsPaging = $true
    $script:LoadAllWritten = -1
    $script:LoadAllUiAt = [DateTime]::MinValue
    Update-PageButton
    if ($script:StatusLbl) { $script:StatusLbl.Text = "Cargando paginas $From-$To..." }
    Write-Log "Cargando paginas $From-$To en lote paralelo..."

    try { Remove-Item $script:LoadAllProgressFile -Force -ErrorAction SilentlyContinue } catch { }

    $script:PageOutFile = Join-Path $env:TEMP ("f1-batch-{0}.log" -f [guid]::NewGuid().ToString('N'))
    $script:PageErrFile = "$($script:PageOutFile).err"

    try {
        $psArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scraperFile,
                    '-DataDir', $scriptDir,
                    '-BatchFrom', [string]$From,
                    '-BatchTo', [string]$To,
                    '-Parallel', '8')
        $script:PageProc = Start-Process -FilePath $psExe -ArgumentList $psArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $script:PageOutFile -RedirectStandardError $script:PageErrFile
    } catch {
        Write-Log "Paginacion: no se pudo lanzar el scraper: $_"
        $script:PageProc = $null
        $script:IsPaging = $false
        Update-PageButton
        return
    }

    if (-not $script:PageTimer) {
        $script:PageTimer = New-Object System.Windows.Forms.Timer
        $script:PageTimer.Interval = 600
        $script:PageTimer.Add_Tick({ Complete-PageLoad })
    }
    $script:PageTimer.Start()
}

function Start-PageLoad {
    if ($script:IsPaging -or $script:NoMorePages) { return }
    $from = [Math]::Max(2, [int]$script:NextPage)
    Start-BatchLoad -From $from -To $from
}

# Captura real de la ventana: PrintWindow incluye el contenido de WebView2
# aunque haya otra ventana delante. DrawToBitmap queda como respaldo.
function Save-WindowShot {
    param([string]$Path, $Form = $null)

    $form = if ($Form) { $Form } else { $script:MainForm }
    if (-not $form -or $form.IsDisposed) { return }
    $bmp = $null
    try {
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        # PW_RENDERFULLCONTENT = 2: pinta tambien el contenido acelerado.
        $ok = [F1.Native]::PrintWindow($form.Handle, $hdc, 2)
        $g.ReleaseHdc($hdc)
        $g.Dispose()
        if (-not $ok) { throw 'PrintWindow no respondio' }
    }
    catch {
        if ($bmp) { $bmp.Dispose() }
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)))
    }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Log "SelfTest: captura de ventana en $Path"
}

# --- Arranque -------------------------------------------------------------
function Save-WebViewPreview {
    param([string]$Name)

    if (-not $script:WebViewCore -or -not $script:WebViewReady) {
        Write-Log "Preview ${Name}: WebView2 no listo"
        return
    }
    try {
        $out = Join-Path $env:TEMP ("f1-selftest-{0}-{1}.png" -f $script:SelfTestMode, $Name)
        $stream = [System.IO.File]::Open($out, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $task = $script:WebViewCore.CapturePreviewAsync([Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat]::Png, $stream)
        $script:PreviewTask = $task
        $script:PreviewStream = $stream
        $script:PreviewOut = $out

        if (-not $script:PreviewTimer) {
            $script:PreviewTimer = New-Object System.Windows.Forms.Timer
            $script:PreviewTimer.Interval = 300
            $script:PreviewTimer.Add_Tick({
                if ($script:PreviewTask -and $script:PreviewTask.IsCompleted) {
                    $script:PreviewTimer.Stop()
                    try { $script:PreviewStream.Dispose() } catch { }
                    if ($script:PreviewTask.IsFaulted) {
                        Write-Log "Preview: error $($script:PreviewTask.Exception.GetBaseException().Message)"
                    }
                    else {
                        Write-Log "Preview: $($script:PreviewOut)"
                    }
                    $script:PreviewTask = $null
                    $script:PreviewStream = $null
                }
            })
        }
        $script:PreviewTimer.Start()
    }
    catch { Write-Log "Preview ${Name}: no se pudo iniciar: $_" }
}

Write-Log "=== Monitor iniciado (PID $PID) ==="
Write-Log "Carpeta: $scriptDir"

# Identidad propia en la barra de tareas: agrupa la ventana con su icono en
# lugar de mezclarla con otros procesos de PowerShell.
try { [void][F1.User32]::SetCurrentProcessExplicitAppUserModelID('Necu.F1TrayMonitor') } catch { }

$script:AppIcon = New-F1Icon
$script:Tip = New-Object System.Windows.Forms.ToolTip

$script:Posts = Load-Posts
foreach ($p in $script:Posts) {
    if ($p.id) { [void]$script:KnownIds.Add([string]$p.id) }
}
Read-State
Read-SourcesCatalog
Build-SearchIndex
# Si ya habia cache, las entradas nuevas que aparezcan en el primer scrapeo SI deben notificarse.
$script:FirstSeed = ($script:Posts.Count -gt 0)
Write-Log "Cache inicial: $($script:Posts.Count) entradas"

$script:Tray = New-Object System.Windows.Forms.NotifyIcon
$script:Tray.Icon = $script:AppIcon
$script:Tray.Text = 'F1 Tray Monitor'
$script:Tray.Visible = $true
$script:Tray.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Toggle-MainWindow }
    elseif ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $script:TrayRightClicked = $true
        Save-State
        Hide-TrayHint
        Show-TrayMenu
    }
})
$script:Tray.Add_BalloonTipClicked({ Show-MainWindow })

Refresh-Menu

# Temporizador periodico de scraping (en ambito de script para poder cambiar
# el intervalo desde Ajustes sin reiniciar).
$script:MainTimer = New-Object System.Windows.Forms.Timer
$script:MainTimer.Interval = [Math]::Max(1, $IntervalMinutes) * 60 * 1000
$script:MainTimer.Add_Tick({
    $today = (Get-Date).DayOfWeek.ToString()
    if ($ScrapeAllDays -or ($script:ScrapeDays -contains $today)) {
        Start-Scrape
    }
    else {
        Write-Log "Fuera de viernes-domingo ($today): sin scraping programado"
        if ($script:StatusLbl) {
            $script:StatusLbl.Text = "En espera (solo vie-dom)  ·  $($script:Posts.Count) entradas"
        }
    }
})
$script:MainTimer.Start()

# Neon rotativo: avanza de equipo cada 12 s si el ajuste esta activo.
$script:NeonTimer = New-Object System.Windows.Forms.Timer
$script:NeonTimer.Interval = 12000
$script:NeonTimer.Add_Tick({
    if ($script:Config.neonCycle) { Step-Neon }
})
Update-NeonTimer

# Primer scrapeo en cuanto arranque el bucle de mensajes
$initTimer = New-Object System.Windows.Forms.Timer
$initTimer.Interval = 400
$initTimer.Add_Tick({
    $initTimer.Stop()
    if ($script:FirstSeed) {
        Show-Balloon 'F1 Tray Monitor' "Monitor activo. $($script:Posts.Count) entradas en caché." 'Info'
    }
    if ($SelfTest) {
        Write-Log 'SelfTest: se omite el scrapeo inicial'
    }
    else {
        Start-SourcesDownload
        Start-Scrape
        Start-UpdateAutoCheck
        if (-not $script:Config.startMinimized) { Show-MainWindow }
        Show-TrayHint
    }
})
$initTimer.Start()

$context = New-Object System.Windows.Forms.ApplicationContext

if ($SelfTest) {
    $script:SelfTestMode = if ($SelfTestAction) { $SelfTestAction.ToLowerInvariant() } else { 'player' }
    Write-Log "SelfTest: mostrando ventana (accion=$($script:SelfTestMode))"
    Show-MainWindow

    $script:SelfTestClick = New-Object System.Windows.Forms.Timer
    $script:SelfTestClick.Interval = 3500
    $script:SelfTestClick.Add_Tick({
        $script:SelfTestClick.Stop()
        switch ($script:SelfTestMode) {
            'search' {
                $casos = @('mexico', 'cdmx', 'interlagos', 'clasi', 'practica', 'qualy', 'brasl', 'castellano dazn')
                foreach ($caso in $casos) {
                    $script:SearchQuery = ConvertTo-SearchText $caso
                    $vis = @(Get-VisiblePosts)
                    $titulos = (@($vis | Select-Object -First 3 | ForEach-Object { $_.title }) -join ' | ')
                    Write-Log "SelfTest search [$caso]: $($vis.Count) resultados -> $titulos"
                }
                $script:SearchBox.Text = 'mexico'
                $script:SearchQuery = ConvertTo-SearchText 'mexico'
                Build-List
                Write-Log "SelfTest search: $($script:Cards.Count) visibles de $($script:Posts.Count) con 'mexico'"
                Write-Log "SelfTest search: contador='$($script:CountLbl.Text)'"
                $script:SearchBox.Text = ''
                $script:SearchQuery = ''
                Build-List
            }
            'accordion' {
                if ($script:Cards.Count -ge 2) {
                    Toggle-Card $script:Cards[0].Id
                    $primera = $script:ExpandedId
                    Toggle-Card $script:Cards[1].Id
                    $abiertas = @($script:Cards | Where-Object { $_.Options.Visible }).Count
                    Write-Log "SelfTest accordion: primera=$primera abiertaAhora=$($script:ExpandedId) tarjetasAbiertas=$abiertas"
                }
                else { Write-Log 'SelfTest accordion: hacen falta 2 tarjetas' }
            }
            'page' {
                Write-Log "SelfTest page: solicitando pagina $($script:NextPage)"
                Start-PageLoad
            }
            'loadall' {
                Write-Log "SelfTest loadall: inicio en la pagina $($script:NextPage) boton='$($script:LoadAllBtn.Text)'"
                Toggle-LoadAllPages
                $script:SelfTestLoadAllCheck = New-Object System.Windows.Forms.Timer
                $script:SelfTestLoadAllCheck.Interval = 26000
                $script:SelfTestLoadAllCheck.Add_Tick({
                    $script:SelfTestLoadAllCheck.Stop()
                    Write-Log "SelfTest loadall: activo=$($script:LoadAll) paginas=$($script:LoadAllPages) total=$($script:Posts.Count) boton='$($script:LoadAllBtn.Text)'"
                    if ($script:LoadAll) { Toggle-LoadAllPages }
                    Write-Log "SelfTest loadall: tras detener activo=$($script:LoadAll) boton='$($script:LoadAllBtn.Text)'"
                })
                $script:SelfTestLoadAllCheck.Start()
            }
            'resize' {
                # Recorre tamanos reales y comprueba que ni el divisor ni las
                # tarjetas imponen limites ni lanzan excepciones.
                $sizes = @(@(1180, 900), @(980, 760), @(820, 620), @(680, 520), @(520, 400), @(1440, 1000), @(1180, 900))
                foreach ($s in $sizes) {
                    $script:MainForm.Size = New-Object System.Drawing.Size($s[0], $s[1])
                    $script:MainForm.PerformLayout()
                    [System.Windows.Forms.Application]::DoEvents()
                    Update-WindowLayout
                    $splitInfo = if ($script:Split) {
                        "split=$($script:Split.Width) d=$($script:Split.SplitterDistance) p1=$($script:Split.Panel1.Width) p2=$($script:Split.Panel2.Width) col=$($script:Split.Panel1Collapsed)"
                    }
                    else { 'sin split' }
                    $cardW = if ($script:Cards.Count -gt 0) { $script:Cards[0].Card.Width } else { 0 }
                    # La cabecera debe caber entera: ningun boton visible puede
                    # quedar fuera del panel ni pisar el titulo.
                    $headNeed = 0
                    $headOut = @()
                    if ($script:HeaderActions) {
                        foreach ($c in $script:HeaderActions.Controls) {
                            if (-not $c.Visible) { continue }
                            $headNeed += $c.Width + $c.Margin.Horizontal
                            if ($c.Left -lt 0 -or $c.Right -gt $script:HeaderActions.ClientSize.Width) {
                                $headOut += ([string]$c.Text).Trim()
                            }
                        }
                    }
                    $headW = if ($script:HeaderActions) { $script:HeaderActions.Width } else { 0 }
                    $headInfo = "cabecera=$headW necesita=$headNeed"
                    if ($headOut.Count -gt 0) { $headInfo += " RECORTA: $($headOut -join ',')" }
                    Write-Log ("SelfTest resize: {0}x{1} {2} tarjeta={3} ratio={4} pagina={5} cargarTodo={6} {7}" -f
                        $s[0], $s[1], $splitInfo, $cardW, [Math]::Round($script:SplitRatio, 2),
                        [bool]$script:NextPageBtn.Visible, [bool]$script:LoadAllBtn.Visible, $headInfo)
                }
                # El divisor ignora los ajustes programaticos: la proporcion no
                # debe cambiar al redimensionar ni al recolocarlo por codigo.
                if ($script:Split -and -not $script:Split.Panel1Collapsed) {
                    $ratioBefore = $script:SplitRatio
                    $script:Split.SplitterDistance = 90
                    [System.Windows.Forms.Application]::DoEvents()
                    Write-Log "SelfTest resize: ajuste programatico a 90 -> ratio=$ratioBefore->$($script:SplitRatio) col=$($script:Split.Panel1Collapsed)"
                    Set-SplitRatio $ratioBefore
                    Set-ListVisible -Visible $false
                    [System.Windows.Forms.Application]::DoEvents()
                    Write-Log "SelfTest resize: ocultar lista -> col=$($script:Split.Panel1Collapsed)"
                    Set-ListVisible -Visible $true
                    [System.Windows.Forms.Application]::DoEvents()
                    Write-Log "SelfTest resize: restaurar lista -> col=$($script:Split.Panel1Collapsed) d=$($script:Split.SplitterDistance) ratio=$([Math]::Round($script:SplitRatio, 2))"
                }
                # Mostrar la ventana no debe reconstruir la lista.
                $before = $script:ListBuildCount
                Show-MainWindow
                Write-Log "SelfTest resize: builds antes=$before despues=$($script:ListBuildCount) (0 = sin reconstruir)"
            }
            'ui' {
                Show-TrayMenu
                Write-Log "SelfTest ui: panel bandeja visible=$($script:TrayMenu.Visible) filas=$($script:TrayMenuList.Controls.Count)"
                # Filtro del panel de bandeja y despliegue de una fila.
                $script:TrayMenuBox.Text = 'interlagos'
                & $script:TrayRebuild
                Write-Log "SelfTest ui: filtro 'interlagos' filas=$($script:TrayMenuList.Controls.Count)"
                if ($script:TrayMenuList.Controls.Count -gt 0) {
                    $row = $script:TrayMenuList.Controls[0]
                    $row.Controls[0].PerformClick()
                    Write-Log "SelfTest ui: fila desplegada alto=$($row.Height) controles=$($row.Controls.Count)"
                }
                $script:TrayMenuBox.Text = ''
                & $script:TrayRebuild
                $script:SelfTestUi = New-Object System.Windows.Forms.Timer
                $script:SelfTestUi.Interval = 900
                $script:SelfTestUi.Add_Tick({
                    $script:SelfTestUi.Stop()
                    Save-WindowShot -Path (Join-Path $env:TEMP 'f1-selftest-tray.png') -Form $script:TrayMenu
                    if ($script:TrayMenu) { try { $script:TrayMenu.Close() } catch { } }
                    Show-Settings
                    Write-Log "SelfTest ui: ajustes visible=$($script:SettingsForm.Visible)"
                    $script:SelfTestUi2 = New-Object System.Windows.Forms.Timer
                    $script:SelfTestUi2.Interval = 1200
                    $script:SelfTestUi2.Add_Tick({
                        $script:SelfTestUi2.Stop()
                        Save-WindowShot -Path (Join-Path $env:TEMP 'f1-selftest-settings.png') -Form $script:SettingsForm
                        $before = [bool]$script:Config.neonCycle
                        $script:Config.neonCycle = -not $before
                        Save-Config
                        Update-NeonTimer
                        Write-Log "SelfTest ui: neonCycle $before -> $($script:Config.neonCycle) neon=$($script:Config.neonTeam) intervalo=$($script:Config.intervalMinutes)"
                        $script:Config.neonCycle = $before
                        Save-Config
                        Update-NeonTimer
                        if ($script:SettingsForm) { try { $script:SettingsForm.Close() } catch { } }
                        Toggle-MainWindow
                        Write-Log "SelfTest ui: tras ocultar visible=$($script:MainForm.Visible)"
                        Toggle-MainWindow
                        Write-Log "SelfTest ui: tras mostrar visible=$($script:MainForm.Visible) estado=$($script:MainForm.WindowState)"
                    })
                    $script:SelfTestUi2.Start()
                })
                $script:SelfTestUi.Start()
            }
            'catalog' {
                $cat = $script:SourcesCatalog
                if ($cat) {
                    $rules = @($cat.rules | Where-Object { $_ })
                    $active = @($rules | Where-Object { Test-RuleActive $_ }).Count
                    Write-Log "SelfTest catalog: version=$($cat.version) reglas=$($rules.Count) activas=$active servicios=$(@($cat.services.PSObject.Properties).Count)"
                    $matched = 0
                    foreach ($p in @($script:Posts | Select-Object -First 40)) {
                        $opts = @(Get-PlayOptions $p)
                        $fromCat = @($opts | Where-Object { $_.origin -eq 'catalog' }).Count
                        if ($fromCat -gt 0) {
                            $matched++
                            Write-Log "SelfTest catalog: [$($p.id)] +$fromCat del catalogo de $($opts.Count) opciones -> $($p.title)"
                        }
                    }
                    Write-Log "SelfTest catalog: entradas con fuentes del catalogo=$matched"
                }
                else { Write-Log 'SelfTest catalog: sin catalogo cargado' }

                $fav = $null
                if ($script:Posts.Count -gt 0) {
                    $fav = Get-FavoriteKey $script:Posts[0]
                    Toggle-Favorite $fav
                    Write-Log "SelfTest catalog: favorito=$fav activo=$(Test-Favorite $fav) total=$(@($script:Favorites).Count)"
                    $script:FavoritesOnly = $true
                    Build-List
                    Write-Log "SelfTest catalog: filtro favoritos visibles=$($script:Cards.Count) de $($script:Posts.Count)"
                    $script:FavoritesOnly = $false
                    Build-List
                    Toggle-Favorite $fav
                    Write-Log "SelfTest catalog: favorito restaurado total=$(@($script:Favorites).Count)"
                }

                $oldHist = @($script:SearchHistory)
                Add-SearchHistory 'verstappen'
                Add-SearchHistory 'interlagos'
                Add-SearchHistory 'verstappen'
                Write-Log "SelfTest catalog: historial=$(@($script:SearchHistory).Count) primero='$(($script:SearchHistory | Select-Object -First 1))'"
                Show-SearchHistory
                Write-Log "SelfTest catalog: sugerencias creadas=$([bool]$script:SearchHistoryForm)"
                Hide-SearchHistory
                $script:SearchHistory = $oldHist
                Save-State
            }
            default {
                $clicked = $false
                foreach ($c in $script:Cards) {
                    if ($c.OptionButtons.Count -gt 0) {
                        $script:ExpandedId = $c.Id
                        foreach ($cc in $script:Cards) { Update-Card $cc }
                        if ($script:ListFlow) { $script:ListFlow.PerformLayout() }
                        $btn = $c.OptionButtons[0]
                        Write-Log "SelfTest: click en la primera opcion ($($btn.Tag.name))"
                        try {
                            $btn.PerformClick()
                            Write-Log 'SelfTest: PerformClick completado'
                        } catch {
                            Write-Log "SelfTest: EXCEPCION en PerformClick: $($_ | Out-String)"
                        }
                        $clicked = $true
                        break
                    }
                }
                if (-not $clicked) { Write-Log 'SelfTest: no hay opciones para clickar' }
            }
        }
    })
    $script:SelfTestClick.Start()

    # Captura del propio formulario, incluido el contenido de WebView2.
    $script:SelfTestShot = New-Object System.Windows.Forms.Timer
    $script:SelfTestShot.Interval = if ($script:SelfTestMode -eq 'video') { 10000 } else { 6500 }
    $script:SelfTestShot.Add_Tick({
        $script:SelfTestShot.Stop()
        try {
            $form = $script:MainForm
            if ($form -and -not $form.IsDisposed) {
                # Muestra la barra como si el raton llegara al borde superior.
                if ($script:SelfTestMode -eq 'video' -and $script:WebViewCore) {
                    try {
                        [void]$script:WebViewCore.ExecuteScriptAsync("window.dispatchEvent(new MouseEvent('mousemove',{clientY:10}));")
                        Start-Sleep -Milliseconds 700
                    } catch { }
                }
                Save-WindowShot -Path (Join-Path $env:TEMP ("f1-selftest-{0}.png" -f $script:SelfTestMode))
            }
        } catch {
            Write-Log "SelfTest: error de captura: $_"
        }
        if ($script:WebViewCore -and $script:WebViewReady) {
            try {
                Write-Log "SelfTest webview: title=[$($script:WebViewCore.DocumentTitle)] source=[$($script:WebViewCore.Source)]"
            } catch { }
            try {
                $wv = $script:WebView
                if ($wv) {
                    $p = $wv.Parent.PointToScreen($wv.Location)
                    $f = $script:MainForm.PointToScreen([System.Drawing.Point]::Empty)
                    Write-Log "SelfTest webview rect: x=$($p.X - $f.X) y=$($p.Y - $f.Y) w=$($wv.Width) h=$($wv.Height) form=$($script:MainForm.Width)x$($script:MainForm.Height)"
                }
            } catch { }
            Save-WebViewPreview -Name 'normal'
        }
        try {
            $form = $script:MainForm
            $pl = $form.PointToScreen([System.Drawing.Point]::new(2, 20))
            $pc = $form.PointToScreen([System.Drawing.Point]::new(600, 400))
            $ll = (($pl.Y -shl 16) -bor ($pl.X -band 0xFFFF))
            $lc = (($pc.Y -shl 16) -bor ($pc.X -band 0xFFFF))
            $hl = [F1.Native]::SendMessage($form.Handle, 0x0084, [IntPtr]::Zero, [IntPtr]$ll).ToInt64()
            $hc = [F1.Native]::SendMessage($form.Handle, 0x0084, [IntPtr]::Zero, [IntPtr]$lc).ToInt64()
            Write-Log "SelfTest ventana: borde=$($form.FormBorderStyle) nchittestIzq=$hl nchittestCentro=$hc"
        } catch { Write-Log "SelfTest ventana: error $_" }
    })
    $script:SelfTestShot.Start()

    # Prueba del modo solo video: se oculta todo y luego se recupera el listado.
    if ($script:SelfTestMode -eq 'video') {
        $script:SelfTestVideoOnly = New-Object System.Windows.Forms.Timer
        $script:SelfTestVideoOnly.Interval = 13000
        $script:SelfTestVideoOnly.Add_Tick({
            $script:SelfTestVideoOnly.Stop()
            Set-VideoOnly -Enabled $true
            Write-Log "SelfTest video: soloVideo=$($script:VideoOnly) listaVisible=$($script:ListVisible)"
            $script:SelfTestVideoOnlyShot = New-Object System.Windows.Forms.Timer
            $script:SelfTestVideoOnlyShot.Interval = 2600
            $script:SelfTestVideoOnlyShot.Add_Tick({
                $script:SelfTestVideoOnlyShot.Stop()
                try {
                    Write-Log ("SelfTest video: split=$($script:Split.Width)x$($script:Split.Height) p2=$($script:Split.Panel2.Width) wv=$($script:WebView.Width)x$($script:WebView.Height)")
                } catch { }
                Save-WindowShot -Path (Join-Path $env:TEMP 'f1-selftest-video-videoonly-window.png')
                Save-WebViewPreview -Name 'videoonly'
            })
            $script:SelfTestVideoOnlyShot.Start()

            # Prueba del canal deck -> anfitrion: el boton "Mostrar listado"
            # del HTML debe recuperar la ventana normal.
            $script:SelfTestDeckClick = New-Object System.Windows.Forms.Timer
            $script:SelfTestDeckClick.Interval = 5000
            $script:SelfTestDeckClick.Add_Tick({
                $script:SelfTestDeckClick.Stop()
                try {
                    [void]$script:WebViewCore.ExecuteScriptAsync("document.getElementById('showList').click()")
                    Write-Log 'SelfTest video: click en Mostrar listado enviado'
                } catch { Write-Log "SelfTest video: error al enviar click: $_" }
                $script:SelfTestDeckCheck = New-Object System.Windows.Forms.Timer
                $script:SelfTestDeckCheck.Interval = 1200
                $script:SelfTestDeckCheck.Add_Tick({
                    $script:SelfTestDeckCheck.Stop()
                    Write-Log "SelfTest video: tras Mostrar listado -> soloVideo=$($script:VideoOnly) listaVisible=$($script:ListVisible) collapsed=$($script:Split.Panel1Collapsed)"
                })
                $script:SelfTestDeckCheck.Start()
            })
            $script:SelfTestDeckClick.Start()
        })
        $script:SelfTestVideoOnly.Start()
    }

    $script:SelfTestEnd = New-Object System.Windows.Forms.Timer
    $script:SelfTestEnd.Interval = if ($script:SelfTestMode -eq 'page') { 75000 } elseif ($script:SelfTestMode -eq 'video') { 28000 } elseif ($script:SelfTestMode -eq 'loadall') { 32000 } else { 18000 }
    $script:SelfTestEnd.Add_Tick({
        $script:SelfTestEnd.Stop()
        Write-Log "SelfTest: cerrando (accion=$($script:SelfTestMode))"
        [System.Windows.Forms.Application]::Exit()
    })
    $script:SelfTestEnd.Start()
}

# Precalentado de la ventana. Con "iniciar en bandeja" la ventana no existe
# hasta el primer clic, y crearla (246 tarjetas + WebView2) tardaba segundos.
# Se construye oculta 2,5 s despues del arranque para que el clic sea inmediato.
if (-not $SelfTest) {
    $script:PrewarmTimer = New-Object System.Windows.Forms.Timer
    $script:PrewarmTimer.Interval = 900
    $script:PrewarmTimer.Add_Tick({
        $script:PrewarmTimer.Stop()
        $script:PrewarmTimer.Dispose()
        $script:PrewarmTimer = $null
        if ($script:MainForm -and -not $script:MainForm.IsDisposed) { return }
        try { Show-MainWindow -Hidden } catch { Write-Log "Prewarm: error $_" }
    })
    $script:PrewarmTimer.Start()
}

[System.Windows.Forms.Application]::Run($context)

