#!/usr/bin/env bash
# Instalador de device-monitor lite para Linux (systemd).
# Pregunta los ajustes, instala el agente como servicio y (opcional) un
# tunel Cloudflare Quick Tunnel, y muestra el QR de conexion.
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

ask() { # ask "peso" "pregunta" "valor_por_defecto" [opciones]
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
TUNNEL="$(ask tunnel 'Exponer por Internet con Cloudflare Quick Tunnel? (s/n)' 'n')"

case "${TUNNEL,,}" in s|si|sí|y|yes) WANT_TUNNEL=1 ;; *) WANT_TUNNEL=0 ;; esac

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

# --- unidad systemd ---------------------------------------------------------
AGENT_ARGS="-addr :${PORT} -name \"${NAME}\""
[ -n "$TOKEN" ] && AGENT_ARGS="$AGENT_ARGS -token \"${TOKEN}\""
[ "$WANT_TUNNEL" -eq 1 ] && AGENT_ARGS="$AGENT_ARGS -public-file ${TUNNEL_URL_FILE}"

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

# --- tunel Cloudflare (opcional) -------------------------------------------
if [ "$WANT_TUNNEL" -eq 1 ]; then
  if ! command -v cloudflared >/dev/null 2>&1; then
    say "Instalando cloudflared..."
    case "$ARCH" in amd64) CF=amd64 ;; arm64) CF=arm64 ;; arm7) CF=arm ;; esac
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF}" \
      -o /usr/local/bin/cloudflared || die "No se pudo instalar cloudflared"
    chmod 0755 /usr/local/bin/cloudflared
  fi
  ok "cloudflared disponible"

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

  cat > "${UNIT_DIR}/${TUNNEL_SERVICE}.service" <<UNIT
[Unit]
Description=device-monitor lite (tunel Cloudflare)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${TUNNEL_BIN} ${PORT} ${TUNNEL_URL_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
  ok "Servicio de tunel creado"
fi

# --- firewall ---------------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active; then
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 && ok "Puerto ${PORT} permitido en ufw"
fi

# --- arrancar ---------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now "${SERVICE}.service" >/dev/null 2>&1 && ok "Agente en marcha"
[ "$WANT_TUNNEL" -eq 1 ] && systemctl enable --now "${TUNNEL_SERVICE}.service" >/dev/null 2>&1 && ok "Tunel en marcha"

LAN_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
LAN_IP="${LAN_IP:-127.0.0.1}"

say ""
say "$(c '1;32' 'Listo.') Escanea el QR con la app device-monitor lite:"
say ""
"$INSTALL_BIN" -qr -name "$NAME" -token "$TOKEN" -url "http://${LAN_IP}:${PORT}"
say ""
if [ "$WANT_TUNNEL" -eq 1 ]; then
  say "En unos segundos tendras tambien el QR de Internet en:"
  say "  http://${LAN_IP}:${PORT}/?t=${TOKEN}"
else
  say "Panel (con la red de casa): http://${LAN_IP}:${PORT}/?t=${TOKEN}"
fi
