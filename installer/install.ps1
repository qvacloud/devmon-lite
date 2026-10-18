# Instalador de device-monitor lite para Windows.
# Pregunta los ajustes, instala el agente como tarea de arranque y (opcional)
# un tunel Cloudflare Quick Tunnel, y muestra el QR de conexion.
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host $m }
function Ok   ($m) { Write-Host "OK  $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "!   $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "x   $m" -ForegroundColor Red; exit 1 }

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Die "Ejecuta el instalador como Administrador (PowerShell como admin)."
}

$BinName   = 'dm-lite'
$Dir       = Join-Path $env:ProgramFiles 'devmon-lite'
$Exe       = Join-Path $Dir "$BinName.exe"
$TunnelExe = Join-Path $Dir 'cloudflared.exe'
$Wrapper   = Join-Path $Dir 'tunnel.ps1'
$UrlFile   = Join-Path $env:ProgramData 'devmon-lite\tunnel.url'

function Ask($question, $default) {
  if ($env:DM_ASSUME_YES) { return $default }
  $ans = Read-Host "$question [$default]"
  if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
  return $ans
}

Say ''
Say '  device-monitor lite - instalador Windows'
Say '  Monitor autoalojado: cada equipo se sirve a si mismo.'
Say ''

$Name   = Ask 'Nombre del equipo' $env:COMPUTERNAME
$Port   = Ask 'Puerto' '55555'
$DefTok = -join ((48..57) + (97..102) | Get-Random -Count 12 | ForEach-Object { [char]$_ })
$Token  = Ask 'Token de acceso (vacio = sin contrasena)' $DefTok
$Disks  = Ask 'Discos a vigilar (separados por coma)' 'C:\'
$Tunnel = Ask 'Exponer por Internet con Cloudflare Quick Tunnel? (s/n)' 'n'
$WantTunnel = ($Tunnel -match '^(s|si|sí|y|yes)$')

# --- binario del agente -----------------------------------------------------
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$candidates = @(
  (Join-Path $PSScriptRoot "$BinName-windows-amd64.exe"),
  (Join-Path $PSScriptRoot "..\dist\$BinName-windows-amd64.exe"),
  $Exe
) | Where-Object { Test-Path $_ }

if ($candidates.Count -gt 0 -and ($candidates[0] -ne $Exe)) {
  Copy-Item -Force $candidates[0] $Exe
  Ok "Agente instalado desde $($candidates[0])"
} elseif (-not (Test-Path $Exe)) {
  Say 'Descargando el agente...'
  $url = 'https://github.com/qvacloud/devmon-lite/releases/latest/download/dm-lite-windows-amd64.exe'
  try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Exe } catch { Die "No se pudo descargar el agente: $_" }
  Ok 'Agente descargado'
}

# --- firewall ---------------------------------------------------------------
if (-not (Get-NetFirewallRule -DisplayName 'device-monitor lite' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName 'device-monitor lite' -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort $Port | Out-Null
  Ok "Puerto $Port permitido en el firewall"
}

# --- entorno de la tarea ----------------------------------------------------
if ($WantTunnel) {
  if (-not (Test-Path $TunnelExe)) {
    Say 'Descargando cloudflared...'
    $cfUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
    try { Invoke-WebRequest -UseBasicParsing -Uri $cfUrl -OutFile $TunnelExe } catch { Die "No se pudo descargar cloudflared: $_" }
  }
  Ok 'cloudflared disponible'

  $wrapperSrc = @'
param([int]$Port = 55555, [string]$Out = "$env:ProgramData\devmon-lite\tunnel.url")
$dir = Split-Path $Out
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$exe = Join-Path $env:ProgramFiles 'devmon-lite\cloudflared.exe'
while ($true) {
  & $exe tunnel --no-autoupdate --url "http://localhost:$Port" 2>&1 | ForEach-Object {
    if ($_ -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
      $matches[0] | Set-Content -Path $Out -Encoding ascii
      Write-Host "tunel: $($matches[0])"
    }
  }
  Start-Sleep -Seconds 5
}
'@
  Set-Content -Path $Wrapper -Value $wrapperSrc -Encoding UTF8

  $actT = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Wrapper`" -Port $Port -Out `"$UrlFile`""
  $trgT = New-ScheduledTaskTrigger -AtStartup
  $prnT = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  Register-ScheduledTask -TaskName 'device-monitor-lite-tunnel' -Action $actT -Trigger $trgT -Principal $prnT -Force | Out-Null
  Start-ScheduledTask -TaskName 'device-monitor-lite-tunnel'
  Ok 'Tunel configurado'
}

# --- tarea del agente -------------------------------------------------------
$agentArgs = "-addr :$Port -name `"$Name`""
if ($Token)      { $agentArgs += " -token `"$Token`"" }
if ($WantTunnel) { $agentArgs += " -public-file `"$UrlFile`"" }

$act = New-ScheduledTaskAction -Execute $Exe -Argument $agentArgs
$trg = New-ScheduledTaskTrigger -AtStartup
$prn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'device-monitor-lite' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null

$env:DISK_MOUNTS = $Disks
Start-ScheduledTask -TaskName 'device-monitor-lite'
Ok 'Agente en marcha'

$lanIp = (Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Select-Object -First 1).IPAddress
if (-not $lanIp) { $lanIp = '127.0.0.1' }

Say ''
Say 'Listo. Escanea el QR con la app device-monitor lite:'
Say ''
& $Exe -qr -name $Name -token $Token -url "http://${lanIp}:${Port}"
Say ''
if ($WantTunnel) {
  Say "En unos segundos tendras el QR de Internet en: http://${lanIp}:${Port}/?t=${Token}"
} else {
  Say "Panel (red de casa): http://${lanIp}:${Port}/?t=${Token}"
}
