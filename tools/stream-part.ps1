# Servidor HTTP local con soporte de Range sobre un archivo que sigue creciendo.
#
# Sirve la base del "ver mientras se descarga": el reproductor pide rangos y este
# proceso entrega los bytes que ya existen, esperando a que el archivo crezca.
# No requiere administrador (TcpListener propio, sin HttpListener ni ACL de URL).
#
#   .\tools\stream-part.ps1 -File C:\descargas\carrera.mp4
#   .\tools\stream-part.ps1 -File .\video.mp4 -Port 8100 -IdleSeconds 15
#
# Endpoints:
#   GET /stream   video con Range (206) o progresivo por chunks (200)
#   GET /health   JSON con tamano actual y tipo MIME
#
# Limitaciones conocidas: WebView2 solo reproduce MP4/H.264+AAC. MKV/HEVC/AC3
# necesitan un reproductor externo o remux con ffmpeg.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$File,
    [int]$Port = 8099,
    [string]$BindAddress = '127.0.0.1',
    [int]$IdleSeconds = 12,
    [int]$ChunkSize = 65536
)

$ErrorActionPreference = 'Stop'

$path = [System.IO.Path]::GetFullPath($File)
if (-not (Test-Path $path)) { throw "No existe el archivo: $path" }

$mimeMap = @{
    '.mp4'  = 'video/mp4'
    '.m4v'  = 'video/mp4'
    '.webm' = 'video/webm'
    '.mkv'  = 'video/x-matroska'
    '.mov'  = 'video/quicktime'
    '.m4a'  = 'audio/mp4'
    '.mp3'  = 'audio/mpeg'
    '.ts'   = 'video/mp2t'
    '.avi'  = 'video/x-msvideo'
}
$ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
$contentType = if ($mimeMap.ContainsKey($ext)) { $mimeMap[$ext] } else { 'application/octet-stream' }

function Get-Length {
    try { return [int64](New-Object System.IO.FileInfo($path)).Length }
    catch { return [int64]0 }
}

function Send-Ascii {
    param($Stream, [string]$Text)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Send-Chunk {
    param($Stream, [byte[]]$Bytes, [int]$Count)
    Send-Ascii $Stream (('{0:X}' -f $Count) + "`r`n")
    $Stream.Write($Bytes, 0, $Count)
    Send-Ascii $Stream "`r`n"
}

function Read-Request {
    param($Stream)
    $buffer = New-Object byte[] 4096
    $sb = New-Object System.Text.StringBuilder
    while ($true) {
        $read = $Stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { break }
        [void]$sb.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $read))
        if ($sb.ToString().Contains("`r`n`r`n")) { break }
        if ($sb.Length -gt 32768) { break }
    }
    return $sb.ToString()
}

function Read-Range {
    param($Stream, [int64]$Offset, [int]$Max)
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        [void]$fs.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $buffer = New-Object byte[] $Max
        $total = 0
        while ($total -lt $Max) {
            $read = $fs.Read($buffer, $total, $Max - $total)
            if ($read -le 0) { break }
            $total += $read
        }
        return @{ Buffer = $buffer; Count = $total }
    }
    finally { $fs.Dispose() }
}

function Wait-ForBytes {
    param([int64]$Offset, [int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Length) -le $Offset) {
        if ((Get-Date) -gt $deadline) { return $false }
        Start-Sleep -Milliseconds 200
    }
    return $true
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($BindAddress), $Port)
try { $listener.Start() }
catch { throw "No se pudo abrir $BindAddress`:$Port ($($_.Exception.Message)). Prueba otro -Port." }

$base = "http://${BindAddress}:$Port"
Write-Host "F1 Tray Monitor - servidor de streaming" -ForegroundColor Cyan
Write-Host "  Archivo : $path ($([Math]::Round((Get-Length) / 1MB, 2)) MB)"
Write-Host "  Stream  : $base/stream"
Write-Host "  Salud   : $base/health"
Write-Host '  Ctrl+C para detener.'
Write-Host ''

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 15000
            $client.SendTimeout = 60000
            $stream = $client.GetStream()
            $raw = Read-Request $stream
            if (-not $raw) { continue }

            $lines = $raw -split "`r`n"
            $request = $lines[0] -split ' '
            if ($request.Count -lt 2) { continue }
            $method = $request[0].ToUpperInvariant()
            $target = ($request[1] -split '\?')[0]

            $headers = @{}
            foreach ($line in @($lines | Select-Object -Skip 1)) {
                if ($line -match '^([A-Za-z0-9\-]+):\s*(.*)$') {
                    $headers[$matches[1].ToLowerInvariant()] = $matches[2].Trim()
                }
            }

            $length = Get-Length

            if ($target -eq '/health') {
                $json = "{`"file`":$(($path | ConvertTo-Json)),`"size`":$length,`"mime`":$(($contentType | ConvertTo-Json))}"
                Send-Ascii $stream "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($json))`r`nConnection: close`r`n`r`n"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $stream.Write($bytes, 0, $bytes.Length)
                continue
            }

            if ($target -ne '/' -and $target -ne '/stream') {
                Send-Ascii $stream "HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
                continue
            }

            $range = [string]$headers['range']
            $start = [int64]0
            $end = [int64]-1
            $hasRange = $false

            if ($range -match 'bytes=(\d*)-(\d*)') {
                $hasRange = $true
                if ($matches[1]) { $start = [int64]$matches[1] }
                if ($matches[2]) { $end = [int64]$matches[2] }
            }

            if ($method -eq 'HEAD') {
                if ($hasRange -and $end -ge $start) {
                    $count = $end - $start + 1
                    Send-Ascii $stream "HTTP/1.1 206 Partial Content`r`nContent-Type: $contentType`r`nAccept-Ranges: bytes`r`nContent-Range: bytes $start-$end/$([Math]::Max($length, $end + 1))`r`nContent-Length: $count`r`nConnection: close`r`n`r`n"
                }
                else {
                    Send-Ascii $stream "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nAccept-Ranges: bytes`r`nContent-Length: $length`r`nConnection: close`r`n`r`n"
                }
                continue
            }

            if (-not $hasRange) {
                # Peticion normal: se envia lo que ya existe.
                Send-Ascii $stream "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nAccept-Ranges: bytes`r`nContent-Length: $length`r`nConnection: close`r`n`r`n"
                $offset = [int64]0
                while ($offset -lt $length) {
                    $want = [int][Math]::Min($ChunkSize, $length - $offset)
                    $data = Read-Range $stream $offset $want
                    if ($data.Count -le 0) { break }
                    $stream.Write($data.Buffer, 0, $data.Count)
                    $offset += $data.Count
                }
                continue
            }

            if ($start -ge $length -and $length -gt 0) {
                Send-Ascii $stream "HTTP/1.1 416 Range Not Satisfiable`r`nContent-Range: bytes */$length`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
                continue
            }

            if ($end -ge $start) {
                # Rango cerrado: se espera a tener los bytes y se responde 206.
                $wantEnd = [Math]::Min($end, [Math]::Max($length - 1, $start))
                if (-not (Wait-ForBytes -Offset ($wantEnd + 1) -Seconds $IdleSeconds)) {
                    $wantEnd = [Math]::Max($start, $length - 1)
                }
                $count = [int64]($wantEnd - $start + 1)
                Send-Ascii $stream "HTTP/1.1 206 Partial Content`r`nContent-Type: $contentType`r`nAccept-Ranges: bytes`r`nContent-Range: bytes $start-$wantEnd/$([Math]::Max($length, $wantEnd + 1))`r`nContent-Length: $count`r`nConnection: close`r`n`r`n"
                $offset = $start
                while ($offset -le $wantEnd) {
                    $want = [int][Math]::Min($ChunkSize, $wantEnd - $offset + 1)
                    if (-not (Wait-ForBytes -Offset ($offset + $want) -Seconds $IdleSeconds)) { break }
                    $data = Read-Range $stream $offset $want
                    if ($data.Count -le 0) { break }
                    $stream.Write($data.Buffer, 0, $data.Count)
                    $offset += $data.Count
                }
                continue
            }

            # Rango abierto. Desde el principio se sirve en chunks para poder ir
            # reproduciendo mientras el archivo crece; desde una posicion se
            # responde una instantanea y el reproductor pedira mas al avanzar.
            if ($start -eq 0) {
                Send-Ascii $stream "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nAccept-Ranges: bytes`r`nTransfer-Encoding: chunked`r`nConnection: close`r`n`r`n"
                $offset = [int64]0
                $stable = 0
                $lastLength = [int64]-1
                while ($true) {
                    $current = Get-Length
                    if ($current -gt $offset) {
                        $want = [int][Math]::Min($ChunkSize, $current - $offset)
                        $data = Read-Range $stream $offset $want
                        if ($data.Count -gt 0) {
                            Send-Chunk $stream $data.Buffer $data.Count
                            $offset += $data.Count
                        }
                        $stable = 0
                        $lastLength = $current
                    }
                    else {
                        if ($current -eq $lastLength) { $stable++ } else { $stable = 0; $lastLength = $current }
                        if ($stable -ge ($IdleSeconds * 5)) { break }
                    }
                    Start-Sleep -Milliseconds 200
                }
                Send-Ascii $stream "0`r`n`r`n"
            }
            else {
                $count = [int64]($length - $start)
                if ($count -le 0) {
                    Send-Ascii $stream "HTTP/1.1 416 Range Not Satisfiable`r`nContent-Range: bytes */$length`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
                    continue
                }
                Send-Ascii $stream "HTTP/1.1 206 Partial Content`r`nContent-Type: $contentType`r`nAccept-Ranges: bytes`r`nContent-Range: bytes $start-$($length - 1)/$length`r`nContent-Length: $count`r`nConnection: close`r`n`r`n"
                $offset = $start
                while ($offset -lt $length) {
                    $want = [int][Math]::Min($ChunkSize, $length - $offset)
                    $data = Read-Range $stream $offset $want
                    if ($data.Count -le 0) { break }
                    $stream.Write($data.Buffer, 0, $data.Count)
                    $offset += $data.Count
                }
            }
        }
        catch {
            Write-Host "Peticion fallida: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
        finally {
            try { $client.Close() } catch { }
        }
    }
}
finally {
    try { $listener.Stop() } catch { }
    Write-Host 'Servidor detenido.'
}
