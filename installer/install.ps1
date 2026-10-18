# Instalador de device-monitor lite para Windows.
# Pregunta los ajustes, instala el agente como tarea de arranque y, opcionalmente,
# un acceso remoto (Cloudflare Quick, Cloudflare fijo o ngrok) que sobrevive a los
# reinicios. Al terminar muestra el QR de conexion.
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
$CfExe     = Join-Path $Dir 'cloudflared.exe'
$NgExe     = Join-Path $Dir 'ngrok.exe'
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

Say ''
Say 'Acceso remoto (sobrevive a los reinicios):'
Say '  1) no (solo LAN, o ya tengo mi propio tunel)'
Say '  2) Cloudflare Quick  (sin cuenta; la URL CAMBIA al reiniciar)'
Say '  3) Cloudflare fijo   (token de tunel; URL estable)'
Say '  4) ngrok             (dominio dev fijo; 20k peticiones/mes)'
$TunnelKind = Ask 'Elige 1-4' '1'

$Public     = ''
$AgentExtra = ''
$WantQuick  = ($TunnelKind -eq '2')

# --- binario del agente -----------------------------------------------------
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$candidates = @(
  (Join-Path $PSScriptRoot "$BinName-windows-amd64.exe"),
  (Join-Path $PSScriptRoot "..\dist\$BinName-windows-amd64.exe")
) | Where-Object { Test-Path $_ }

if ($candidates.Count -gt 0) {
  Copy-Item -Force $candidates[0] $Exe
  Ok "Agente instalado desde $($candidates[0])"
} elseif (-not (Test-Path $Exe)) {
  Say 'Descargando el agente...'
  $url = 'https://github.com/qvacloud/devmon-lite/releases/latest/download/dm-lite-windows-amd64.exe'
  try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Exe } catch { Die "No se pudo descargar el agente: $_" }
  Ok 'Agente descargado'
}

function Ensure-Cloudflared {
  if (Test-Path $CfExe) { return }
  Say 'Descargando cloudflared...'
  $u = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
  try { Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $CfExe } catch { Die "No se pudo descargar cloudflared: $_" }
  Ok 'cloudflared disponible'
}

function Ensure-Ngrok {
  if (Test-Path $NgExe) { return }
  Say 'Descargando ngrok...'
  $zip = Join-Path $env:TEMP 'ngrok.zip'
  try { Invoke-WebRequest -UseBasicParsing -Uri 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip' -OutFile $zip } catch { Die "No se pudo descargar ngrok: $_" }
  Expand-Archive -Force -Path $zip -DestinationPath $Dir
  Remove-Item -Force $zip
  Ok 'ngrok disponible'
}

function Register-TunnelTask($arguments) {
  $act = New-ScheduledTaskAction -Execute $arguments[0] -Argument $arguments[1]
  $trg = New-ScheduledTaskTrigger -AtStartup
  $prn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $set = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName 'device-monitor-lite-tunnel' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
  Start-ScheduledTask -TaskName 'device-monitor-lite-tunnel'
}

switch ($TunnelKind) {
  '2' {
    Ensure-Cloudflared
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
    Register-TunnelTask @('powershell.exe', "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Wrapper`" -Port $Port -Out `"$UrlFile`"")
    $AgentExtra = "-public-file `"$UrlFile`""
    Ok 'Tunel Cloudflare Quick configurado'
  }
  '3' {
    Ensure-Cloudflared
    Say '  Crea el tunel en el panel de Cloudflare, anade el hostname publico'
    Say '  apuntando a http://localhost:PUERTO y copia el token del tunel.'
    $CfToken = Ask 'Token del tunel de Cloudflare' ''
    if (-not $CfToken) { Die 'Sin token no puedo crear el tunel fijo.' }
    $Public = Ask 'URL publica (tu hostname, p.ej. casa.midominio.com)' ''
    Register-TunnelTask @($CfExe, "tunnel --no-autoupdate run --token $CfToken")
    if ($Public) { $AgentExtra = "-public `"https://$($Public -replace '^https?://','')`"" }
    Ok 'Tunel Cloudflare fijo configurado'
  }
  '4' {
    Ensure-Ngrok
    $NgToken = Ask 'Authtoken de ngrok (dashboard.ngrok.com)' ''
    if (-not $NgToken) { Die 'Sin authtoken no puedo crear el tunel de ngrok.' }
    $Public = Ask 'Tu dominio dev de ngrok (p.ej. abc123.ngrok-free.app)' ''
    if (-not $Public) { Die 'Sin dominio dev no puedo crear el tunel de ngrok.' }
    & $NgExe config add-authtoken $NgToken | Out-Null
    Register-TunnelTask @($NgExe, "http $Port --url https://$($Public -replace '^https?://','') --log stdout")
    $AgentExtra = "-public `"https://$($Public -replace '^https?://','')`""
    Ok 'Tunel ngrok configurado (dominio fijo)'
  }
  default { Ok "Sin tunel: solo red local (o usa tu propio tunel apuntando a localhost:$Port)" }
}

# --- firewall ---------------------------------------------------------------
if (-not (Get-NetFirewallRule -DisplayName 'device-monitor lite' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName 'device-monitor lite' -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort $Port | Out-Null
  Ok "Puerto $Port permitido en el firewall"
}

# --- tarea del agente -------------------------------------------------------
$agentArgs = "-addr :$Port -name `"$Name`""
if ($Token)      { $agentArgs += " -token `"$Token`"" }
if ($AgentExtra) { $agentArgs += " $AgentExtra" }

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

if ($WantQuick -and -not $Public) {
  for ($i = 0; $i -lt 20; $i++) {
    if (Test-Path $UrlFile) { $Public = (Get-Content $UrlFile -Raw).Trim(); if ($Public) { break } }
    Start-Sleep -Seconds 1
  }
}
if ($Public) {
  Say ''
  Say 'QR desde Internet (URL estable, sobrevive reinicios):'
  Say ''
  & $Exe -qr -name $Name -token $Token -url $Public
} else {
  Say ''
  Say "Panel (red de casa): http://${lanIp}:${Port}/?t=${Token}"
}
Say ''
Say 'Todo arranca solo al encender el equipo (tareas programadas de Windows).'
