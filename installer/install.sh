#!/usr/bin/env bash
# Instalador de device-monitor lite para Linux (systemd).
# Pregunta los ajustes, instala el agente como servicio y, opcionalmente, un
# acceso remoto (Cloudflare Quick, Cloudflare fijo o ngrok) que sobrevive a los
# reinicios. Al terminar muestra el QR de conexion.
set -euo pipefail

BIN_NAME="dm-lite"
SERVICE="dm-lite"
TUNNEL_SERVICE="dm-lite-tunnel"
INSTALL_BIN="/usr/local/bin/${BIN_NAME}"
TUNNEL_BIN="/usr/local/bin/${BIN_NAME}-tunnel"
UNIT_DIR="/etc/systemd/system"
TUNNEL_URL_FILE="/run/dm-lite/tunnel.url"

c()  { printf '\033[%sm%s\033[0m' "$1" "$2"; }
say(){ printf '%s\n' "$*"; }
ok() { printf '%s %s\n' "$(c '1;32' '✓')" "$*"; }
warn(){ printf '%s %s\n' "$(c '1;33' '!')" "$*"; }
die(){ printf '%s %s\n' "$(c '1;31' 'x')" "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Ejecuta el instalador como root (sudo bash install.sh)."

ask() { # ask "peso" "pregunta" "valor_por_defecto"
  local def="$3" ans
  if [ -n "${DM_ASSUME_YES:-}" ]; then printf '%s' "$def"; return; fi
  read -r -p "$(c '1;36' '?') $2 $(c '2' "[$def]") " ans || true
  printf '%s' "${ans:-$def}"
}

# --- arquitectura -----------------------------------------------------------
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  armv7l|armv6l|arm) ARCH=arm7 ;;
  *) die "Arquitectura no soportada: $(uname -m)" ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN=""
for cand in "$HERE/${BIN_NAME}-linux-${ARCH}" "$HERE/../dist/${BIN_NAME}-linux-${ARCH}" "$HERE/${BIN_NAME}"; do
  [ -f "$cand" ] && { LOCAL_BIN="$cand"; break; }
done

say ""
say "$(c '1;32' '  device-monitor lite') · instalador Linux (${ARCH})"
say "$(c '2' '  Monitor autoalojado: cada equipo se sirve a si mismo.')"
say ""

# --- ajustes ----------------------------------------------------------------
NAME="$(ask name 'Nombre del equipo' "$(hostname)")"
PORT="$(ask port 'Puerto' '55555')"
DEF_TOKEN="$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
TOKEN="$(ask token 'Token de acceso (vacio = sin contrasena)' "$DEF_TOKEN")"
DISKS="$(ask disks 'Discos a vigilar (separados por coma)' '/')"

say ""
say "Acceso remoto (sobrevive a los reinicios):"
say "  $(c '1' 1)) no, solo en casa"
say "  $(c '1' 2)) Cloudflare Quick  (sin cuenta; la URL CAMBIA al reiniciar)"
say "  $(c '1' 3)) Cloudflare fijo   (token de tunel; URL estable)"
say "  $(c '1' 4)) ngrok             (dominio dev fijo; 20k peticiones/mes)"
TUNNEL_KIND="$(ask tunnel 'Elige 1-4' '1')"

PUBLIC=""        # URL publica conocida (tuneles fijos)
PUBLIC_ARGS=""   # args extra para el agente

# --- binario del agente -----------------------------------------------------
if [ -n "$LOCAL_BIN" ]; then
  install -m 0755 "$LOCAL_BIN" "$INSTALL_BIN"
  ok "Agente instalado desde $LOCAL_BIN"
else
  say "Descargando el agente..."
  URL="https://github.com/qvacloud/devmon-lite/releases/latest/download/${BIN_NAME}-linux-${ARCH}"
  curl -fsSL "$URL" -o "$INSTALL_BIN" || die "No se pudo descargar el agente ($URL)"
  chmod 0755 "$INSTALL_BIN"
  ok "Agente descargado"
fi

install_cloudflared() {
  command -v cloudflared >/dev/null 2>&1 && return 0
  say "Instalando cloudflared..."
  local cf=amd64; case "$ARCH" in arm64) cf=arm64 ;; arm7) cf=arm ;; esac
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf}" \
    -o /usr/local/bin/cloudflared || die "No se pudo instalar cloudflared"
  chmod 0755 /usr/local/bin/cloudflared
  ok "cloudflared disponible"
}

install_ngrok() {
  command -v ngrok >/dev/null 2>&1 && return 0
  say "Instalando ngrok..."
  local ng=amd64; case "$ARCH" in arm64) ng=arm64 ;; arm7) ng=arm ;; esac
  local zip=/tmp/ngrok.zip
  curl -fsSL "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${ng}.zip" -o "$zip" \
    || die "No se pudo descargar ngrok"
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$zip" -d /usr/local/bin
  else
    python3 -c "import zipfile;zipfile.ZipFile('$zip').extractall('/usr/local/bin')" \
      || die "Necesito 'unzip' o python3 para extraer ngrok"
  fi
  chmod 0755 /usr/local/bin/ngrok
  rm -f "$zip"
  ok "ngrok disponible"
}

write_tunnel_unit() { # write_tunnel_unit "<ExecStart>"
  cat > "${UNIT_DIR}/${TUNNEL_SERVICE}.service" <<UNIT
[Unit]
Description=device-monitor lite (acceso remoto)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
  chmod 600 "${UNIT_DIR}/${TUNNEL_SERVICE}.service"
}

case "$TUNNEL_KIND" in
  2)
    install_cloudflared
    cat > "$TUNNEL_BIN" <<'WRAP'
#!/usr/bin/env bash
set -u
PORT="${1:-55555}"; OUT="${2:-/run/dm-lite/tunnel.url}"
mkdir -p "$(dirname "$OUT")"
while true; do
  cloudflared tunnel --no-autoupdate --url "http://localhost:${PORT}" 2>&1 | \
  while IFS= read -r line; do
    url="$(printf '%s' "$line" | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | head -n1 || true)"
    if [ -n "$url" ]; then printf '%s\n' "$url" > "$OUT"; echo "tunel: $url"; fi
  done
  sleep 5
done
WRAP
    chmod 0755 "$TUNNEL_BIN"
    write_tunnel_unit "${TUNNEL_BIN} ${PORT} ${TUNNEL_URL_FILE}"
    PUBLIC_ARGS="-public-file ${TUNNEL_URL_FILE}"
    ok "Servicio de tunel Cloudflare Quick creado"
    ;;
  3)
    install_cloudflared
    say "$(c '2' '  Crea el tunel en el panel de Cloudflare, anade el hostname publico')"
    say "$(c '2' '  apuntando a http://localhost:PUERTO y copia el token del tunel.')"
    CF_TOKEN="$(ask cftoken 'Token del tunel de Cloudflare' '')"
    [ -n "$CF_TOKEN" ] || die "Sin token no puedo crear el tunel fijo."
    PUBLIC="$(ask public 'URL publica (tu hostname, p.ej. casa.midominio.com)' '')"
    write_tunnel_unit "/usr/local/bin/cloudflared --no-autoupdate tunnel run --token ${CF_TOKEN}"
    [ -n "$PUBLIC" ] && PUBLIC_ARGS="-public https://${PUBLIC#https://}"
    ok "Servicio de tunel Cloudflare fijo creado"
    ;;
  4)
    install_ngrok
    NG_TOKEN="$(ask ngtoken 'Authtoken de ngrok (dashboard.ngrok.com)' '')"
    [ -n "$NG_TOKEN" ] || die "Sin authtoken no puedo crear el tunel de ngrok."
    PUBLIC="$(ask public 'Tu dominio dev de ngrok (p.ej. abc123.ngrok-free.app)' '')"
    [ -n "$PUBLIC" ] || die "Sin dominio dev no puedo crear el tunel de ngrok."
    ngrok config add-authtoken "$NG_TOKEN" >/dev/null 2>&1
    write_tunnel_unit "/usr/local/bin/ngrok http ${PORT} --url https://${PUBLIC#https://} --log stdout"
    PUBLIC_ARGS="-public https://${PUBLIC#https://}"
    ok "Servicio de tunel ngrok creado (dominio fijo)"
    ;;
  *) ok "Sin acceso remoto: solo red local" ;;
esac

# --- unidad systemd del agente ----------------------------------------------
AGENT_ARGS="-addr :${PORT} -name \"${NAME}\""
[ -n "$TOKEN" ] && AGENT_ARGS="$AGENT_ARGS -token \"${TOKEN}\""
[ -n "$PUBLIC_ARGS" ] && AGENT_ARGS="$AGENT_ARGS ${PUBLIC_ARGS}"

cat > "${UNIT_DIR}/${SERVICE}.service" <<UNIT
[Unit]
Description=device-monitor lite (agente de metricas)
After=network-online.target
Wants=network-online.target

[Service]
Environment=DISK_MOUNTS=${DISKS}
ExecStart=${INSTALL_BIN} ${AGENT_ARGS}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

# --- firewall ---------------------------------------------------------------
command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active && \
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 && ok "Puerto ${PORT} permitido en ufw"

# --- arrancar ---------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now "${SERVICE}.service" >/dev/null 2>&1 && ok "Agente en marcha"
if [ "$TUNNEL_KIND" != "1" ]; then
  systemctl enable --now "${TUNNEL_SERVICE}.service" >/dev/null 2>&1 && ok "Acceso remoto en marcha"
fi

LAN_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
LAN_IP="${LAN_IP:-127.0.0.1}"

# En tuneles Quick la URL aparece en unos segundos; esperala.
if [ "$TUNNEL_KIND" = "2" ]; then
  for _ in $(seq 1 20); do
    [ -s "$TUNNEL_URL_FILE" ] && { PUBLIC="$(cat "$TUNNEL_URL_FILE")"; break; }
    sleep 1
  done
fi

say ""
say "$(c '1;32' 'Listo.') Escanea el QR con la app device-monitor lite:"
say ""
"$INSTALL_BIN" -qr -name "$NAME" -token "$TOKEN" -url "http://${LAN_IP}:${PORT}"
if [ -n "$PUBLIC" ]; then
  say ""
  say "QR desde Internet (URL estable, sobrevive reinicios):"
  say ""
  "$INSTALL_BIN" -qr -name "$NAME" -token "$TOKEN" -url "$PUBLIC"
else
  say ""
  say "Panel (red de casa): http://${LAN_IP}:${PORT}/?t=${TOKEN}"
fi
say ""
say "Todo arranca solo al encender el equipo (systemd). Revisa con:"
say "  systemctl status ${SERVICE} ${TUNNEL_SERVICE}"
