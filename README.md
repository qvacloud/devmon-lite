# device-monitor lite

Monitor **autoalojado y sin servidor central** pensado para cualquiera. Instalas un
pequeño agente en tu PC (Windows o Linux), abre un panel con un **codigo QR**, y desde
el movil lo escaneas para vigilarlo. No hay que crear cuentas ni contratar nada.

```
PC de casa        Orange Pi        Portatil
 [ agente ]        [ agente ]      [ agente ]      <- cada uno se sirve solo en :55555
     \                 |               /
      \____ app movil: escanea el QR __/
```

## Que incluye

| Carpeta | Que es |
|---|---|
| `agent/` | Agente en Go: API `/metrics`, `/health` y panel con QR (`:55555`) |
| `collector/` | Lectura de CPU/RAM/temp/discos, multiplataforma (linux/windows) |
| `app/` | App Android (Java puro, sin Gradle ni AndroidX) con escaner de QR |
| `installer/` | `install.sh` (Linux) e `install.ps1` (Windows), interactivos |

## Instalar el agente

**Linux** (necesita root, usa systemd):

```bash
sudo bash installer/install.sh
```

**Windows** (PowerShell como Administrador):

```powershell
powershell -ExecutionPolicy Bypass -File installer\install.ps1
```

Ambos preguntan nombre, puerto, token, discos y el **acceso remoto** (solo LAN,
Cloudflare Quick, Cloudflare fijo o ngrok), y al terminar **muestran un QR** para
escanear con la app. Todo queda como servicio que arranca solo al encender el equipo.

### Manual (sin instalador)

```bash
go build -o dm-lite ./agent
./dm-lite -name "PC de casa" -token M1TOKEN
# -> panel en http://<tu-ip>:55555/?t=M1TOKEN
```

Flags: `-addr` `-token` `-name` `-public` `-public-file` `-interval`. Con `-qr` imprime
el QR y el enlace y sale (util para scripts).

## La app

- **Anade equipos escaneando el QR** (o pegando el enlace `devmon://...`).
- **Pantalla siempre encendida** (ajustable) para dejarla de panel de control.
- **Detector de caidas**: te avisa cuando un equipo deja de responder y cuanto estuvo caido.
- **Alertas locales** de CPU, memoria, temperatura y disco, con umbrales configurables.
- Todo **local en el movil**: no depende de ningun servidor.

Compilar:

```bash
make apk     # -> dist/devmon-lite.apk   (necesita ANDROID_HOME; sin Gradle)
```

## Acceso desde fuera de casa

El instalador ofrece cuatro opciones y **configura el arranque automático** (systemd en
Linux, tareas programadas en Windows), asi que el agente y el tunel **sobreviven a los
reinicios**. Como la URL del tunel es publica, **usa siempre un `-token`**.

| Opcion | Cuenta | URL | Sobrevive reinicios |
|---|---|---|---|
| 1) Solo LAN | no | `http://<ip>:55555` | si (IP local) |
| 2) Cloudflare Quick | no | `*.trycloudflare.com` | **no**: la URL cambia |
| 3) Cloudflare fijo | Cloudflare + dominio | tu hostname | **si** (fija, peticiones ilimitadas) |
| 4) ngrok | ngrok (gratis) | `<algo>.ngrok-free.app` | **si** (dominio dev fijo) |

Notas:
- **Cloudflare Quick** no necesita cuenta, pero la URL cambia al reiniciar. El agente la
  relee sola (`-public-file`), pero tendras que **volver a escanear** el QR tras un reinicio.
- **Cloudflare fijo**: crea el tunel en el panel, anade un hostname publico hacia
  `http://localhost:55555`, copia el token del tunel y pasalo al instalador. Peticiones
  ilimitadas.
- **ngrok**: crea una cuenta gratis, copia tu authtoken y tu dominio dev
  (`algo.ngrok-free.app`). El dominio dev es **fijo y no caduca**. Limite del plan gratis:
  **20.000 peticiones/mes** (con la app abierta sondeando cada 5 s lo agotas en ~28 h),
  asi que usalo para consultas ocasionales, no como panel permanente.

El objetivo de "sobrevivir al tiempo" lo cumplen las opciones 1, 3 y 4; la 3 es la unica
**fija e ilimitada** (a cambio de necesitar un dominio propio).


## Compilar todo

```bash
make check     # go vet + build
make cross     # linux/amd64, arm64, arm7  -> dist/dm-lite-linux-*
make windows   # windows/amd64, arm64      -> dist/dm-lite-windows-*.exe
make apk       # dist/devmon-lite.apk
make all       # cross + windows
```

Sin CGO y sin dependencias externas en tiempo de ejecucion (ZXing va vendorizado en
`app/libs/zxing-core.jar` y el QR del agente en `vendor/`).

## Licencia

MIT. Ver [LICENSE](LICENSE).
