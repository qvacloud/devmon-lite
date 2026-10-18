# AGENTS.md

Guia para agentes de IA (y humanos) que trabajen en `devmon-lite`.

## Que es esto

Edicion "de consumo" de device-monitor. Cada equipo ejecuta **un unico binario Go**
(el *agente*) que sirve un API JSON en `:55555` y un panel con **codigo QR**. No hay
servidor central; la app Android (el cliente) escanea el QR y hace polling de varios
equipos. Objetivos: cero dependencias externas en runtime, sin CGO, builds offline,
huella minima.

## Estructura

```
agent/main.go              servidor HTTP: /metrics /health / (panel con QR) + -qr ASCII
agent/web/index.html       panel embebido (//go:embed)
collector/                 recoleccion portable (ver "Contrato de plataforma")
app/                       app Android en Java puro (sin AndroidX/Gradle)
app/build-apk.sh           compilacion offline (aapt2+javac+d8+zipalign+apksigner)
app/libs/zxing-core.jar    ZXing core vendorizado (escaner de QR)
installer/install.sh       instalador Linux (systemd, tunel opcional)
installer/install.ps1      instalador Windows (tarea de arranque, tunel opcional)
vendor/                    dependencias Go vendorizadas (skip2/go-qrcode) para build offline
```

## Build y test

```bash
make check     # go vet ./...  +  go build ./...
gofmt -l .     # debe imprimir nada
make cross     # linux/amd64, linux/arm64, linux/arm7
make windows   # windows/amd64, windows/arm64
make apk       # dist/devmon-lite.apk (necesita ANDROID_HOME; sin Gradle)
```

La compilacion cruzada debe seguir funcionando para **todos** los targets.
Smoke test en Linux:

```bash
go build -o /tmp/dm ./agent && /tmp/dm -addr :55999 -token t &
curl -s http://127.0.0.1:55999/health            # -> ok
curl -s -H 'X-Auth-Token: t' http://127.0.0.1:55999/metrics   # -> JSON
curl -s "http://127.0.0.1:55999/?t=t" | grep -c 'data:image/png;base64,'  # -> 1 (QR)
```

## Contrato de plataforma

El codigo por SO vive en `collector/*_linux.go` y `collector/*_windows.go`, elegidos
por `//go:build`. La logica comun (tipos, `usage`, `temps`, `pct`/`round1`, `normModel`)
vive en ficheros sin etiqueta y es agnostica al SO. Para **anadir un SO** crea
`collector/<name>_<goos>.go` implementando: `readCPUStat`, `cpuCount`, `cpuModel`,
`memInfo`, `loadavg`, `uptime`, `rawTemps`, `diskMounts`, `disks`.
Windows usa **solo** `syscall.NewLazyDLL(...)` — nada de CGO ni modulos de terceros.

Huecos conocidos en Windows (documentar, no falsear): temperaturas (`temp_windows.go`
devuelve `nil`) y `loadavg` (`0`).

## Contrato JSON y enlaces (importante)

- El esquema de `Metrics` (`collector/collector.go`) es el contrato publico que consume
  la app. Cambialo con cuidado.
- El **QR** codifica `devmon://add?n=<nombre>&u=<url>&t=<token>` (`agent/main.go:addLink`,
  parseado en `app/.../Protocol.java`). No rompas el formato sin actualizar ambos lados.
- Con `-token`, `/metrics`, `/` y el QR requieren `X-Auth-Token` o `?t=`. El panel con
  QR es sensible: si se expone por tunel, va con token obligatorio.

## Convenciones

- El espanol se usa en docs/comentarios de cara al usuario; los identificadores en ingles.
- App Android en Java puro (`com.qvacloud.devmon.lite`), **sin AndroidX**. La UI se
  construye por codigo (sin recursos XML).
- **Nunca** commitear IPs, hostnames, contrasenas ni claves reales; en docs usar
  ejemplos `192.168.x.x`. `dist/`, `app/build/`, `*.apk`, `*.exe` y keystores van
  gitignored. `app/libs/zxing-core.jar` y `vendor/` **si** se commitean (necesarios
  para compilar offline).
- `DISK_MOUNTS` (p.ej. `"/,/home"` o `"C:\\"`) limita los discos vigilados.

## Releases

```bash
make cross && make windows && make apk
gh release create vX.Y.Z dist/devmon-lite.apk \
  dist/dm-lite-linux-amd64 dist/dm-lite-linux-arm64 dist/dm-lite-linux-arm7 \
  dist/dm-lite-windows-amd64.exe dist/dm-lite-windows-arm64.exe \
  --title "vX.Y.Z" --notes "..."
```
