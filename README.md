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

Ambos preguntan nombre, puerto, token, discos y si quieres **exponerlo por Internet con
un tunel de Cloudflare**, y al terminar **muestran un QR** para escanear con la app.

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

El instalador puede activar un **Cloudflare Quick Tunnel** (sin cuenta ni dominio) que
da una URL publica temporal y la mete en el QR de Internet. Como esa URL es publica,
**usa siempre un `-token`**. La URL cambia al reiniciar el tunel; el agente la relee
sola (`-public-file`). Para una URL fija hace falta un *named tunnel* con tu propio
dominio (requiere cuenta de Cloudflare).

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
