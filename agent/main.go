// Command dm-agent-lite is the self-hosted metrics agent for the consumer
// edition of device-monitor. Every host serves its own JSON API on :55555 and
// presents a friendly setup page with a QR code the phone app can scan.
package main

import (
	"crypto/rand"
	"embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/qvacloud/devmon-lite/collector"
	"github.com/skip2/go-qrcode"
)

//go:embed web/index.html
var webFS embed.FS

const version = "1.0.0"

type options struct {
	addr       string
	token      string
	name       string
	public     string
	publicFile string
	interval   time.Duration
	qrOnly     bool
	qrURL      string
}

type server struct {
	opts options
	col  *collector.Collector
	page string
}

func main() {
	var o options
	flag.StringVar(&o.addr, "addr", ":55555", "direccion de escucha, p.ej. :55555")
	flag.StringVar(&o.token, "token", "", "token de acceso (vacio = sin autenticacion)")
	flag.StringVar(&o.name, "name", "", "nombre visible del equipo (vacio = hostname)")
	flag.StringVar(&o.public, "public", "", "URL publica (tunel Cloudflare) para el QR remoto")
	flag.StringVar(&o.publicFile, "public-file", "", "archivo con la URL publica actual (se relee en cada visita)")
	flag.DurationVar(&o.interval, "interval", 2*time.Second, "intervalo de muestreo de CPU")
	flag.BoolVar(&o.qrOnly, "qr", false, "imprime el QR y el enlace del equipo, y sale")
	flag.StringVar(&o.qrURL, "url", "", "URL base usada al generar el QR con -qr")
	flag.Parse()

	if o.name == "" {
		o.name, _ = os.Hostname()
	}
	if o.name == "" {
		o.name = "equipo"
	}
	if o.token == "" && !o.qrOnly {
		o.token = randomToken()
		log.Printf("AVISO: no se paso -token; se genero uno temporal %q", o.token)
	}

	col := collector.New()

	if o.qrOnly {
		base := o.qrURL
		if base == "" {
			base = o.publicURL()
		}
		if base == "" {
			base = "http://" + lanHost(o.addr) + ":" + port(o.addr)
		}
		printQR(o.name, base, o.token)
		return
	}

	col.Start(o.interval)
	defer col.Stop()

	raw, err := webFS.ReadFile("web/index.html")
	if err != nil {
		log.Fatalf("no se pudo cargar la pagina: %v", err)
	}

	s := &server{opts: o, col: col, page: string(raw)}

	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleIndex)
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/metrics", s.handleMetrics)

	log.Printf("device-monitor lite %s  |  equipo=%q  escucha=%s", version, o.name, o.addr)
	if o.token != "" {
		log.Printf("token: %s", o.token)
	}
	if pub := o.publicURL(); pub != "" {
		log.Printf("publico: %s", pub)
	}
	log.Printf("panel local: http://%s:%s/?t=%s", lanHost(o.addr), port(o.addr), o.token)

	if err := http.ListenAndServe(o.addr, mux); err != nil {
		log.Fatal(err)
	}
}

func (s *server) authed(r *http.Request) bool {
	if s.opts.token == "" {
		return true
	}
	if r.Header.Get("X-Auth-Token") == s.opts.token {
		return true
	}
	return r.URL.Query().Get("t") == s.opts.token
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte("ok"))
}

func (s *server) handleMetrics(w http.ResponseWriter, r *http.Request) {
	if !s.authed(r) {
		http.Error(w, "no autorizado", http.StatusUnauthorized)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(s.col.Collect())
}

func (s *server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if !s.authed(r) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(lockedPage))
		return
	}

	lanBase := "http://" + lanHost(s.opts.addr) + ":" + port(s.opts.addr)
	public := s.opts.publicURL()

	cfg := map[string]any{
		"name":      s.opts.name,
		"token":     s.opts.token,
		"version":   version,
		"hasPublic": public != "",
		"lanURL":    lanBase,
		"publicURL": public,
	}
	cfgJSON, _ := json.Marshal(cfg)

	page := s.page
	page = strings.ReplaceAll(page, "__NAME__", htmlEscape(s.opts.name))
	page = strings.ReplaceAll(page, "__TOKEN__", htmlEscape(s.opts.token))
	page = strings.ReplaceAll(page, "__VERSION__", version)
	page = strings.ReplaceAll(page, "__LAN_URL__", htmlEscape(lanBase))
	page = strings.ReplaceAll(page, "__QR_LAN__", qrDataURI(addLink(s.opts.name, lanBase, s.opts.token)))
	page = strings.ReplaceAll(page, "__CONFIG_JSON__", string(cfgJSON))

	if public != "" {
		page = strings.ReplaceAll(page, "__PUBLIC_CARD__", publicCard(s.opts.name, public, s.opts.token))
	} else {
		page = strings.ReplaceAll(page, "__PUBLIC_CARD__", "")
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(page))
}

func publicCard(name, base, token string) string {
	return `<div class="card">
      <h2>Acceso desde fuera de casa</h2>
      <p>Escanea este QR para controlarlo desde cualquier sitio (tunel Cloudflare).</p>
      <img class="qr" alt="QR remoto" src="` + qrDataURI(addLink(name, base, token)) + `">
      <code>` + htmlEscape(base) + `</code>
    </div>`
}

func (o options) publicURL() string {
	if o.publicFile != "" {
		if b, err := os.ReadFile(o.publicFile); err == nil {
			if v := strings.TrimSpace(string(b)); v != "" {
				return v
			}
		}
	}
	return o.public
}

func addLink(name, base, token string) string {
	q := url.Values{}
	q.Set("n", name)
	q.Set("u", base)
	if token != "" {
		q.Set("t", token)
	}
	return "devmon://add?" + q.Encode()
}

func qrDataURI(content string) string {
	png, err := qrcode.Encode(content, qrcode.Medium, 320)
	if err != nil {
		return ""
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(png)
}

func printQR(name, base, token string) {
	link := addLink(name, base, token)
	qr, err := qrcode.New(link, qrcode.Medium)
	if err != nil {
		log.Fatalf("no se pudo generar el QR: %v", err)
	}
	fmt.Println(qr.ToSmallString(false))
	fmt.Println("Equipo :", name)
	fmt.Println("Enlace :", link)
	if token != "" {
		fmt.Println("Token  :", token)
	}
	fmt.Println("Escanea el QR con la app device-monitor lite.")
}

func randomToken() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func port(addr string) string {
	if i := strings.LastIndex(addr, ":"); i >= 0 {
		return addr[i+1:]
	}
	return addr
}

func lanHost(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err == nil && host != "" && host != "0.0.0.0" && host != "::" {
		return host
	}
	if ip := firstLANIP(); ip != "" {
		return ip
	}
	return "127.0.0.1"
}

func firstLANIP() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, ifc := range ifaces {
		if ifc.Flags&net.FlagUp == 0 || ifc.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := ifc.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip4 := ipnet.IP.To4()
			if ip4 == nil || ip4.IsLoopback() {
				continue
			}
			if ip4.IsPrivate() {
				return ip4.String()
			}
		}
	}
	return ""
}

func htmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&#34;", "'", "&#39;")
	return r.Replace(s)
}

const lockedPage = `<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Acceso protegido</title>
<style>body{background:#000;color:#39FF14;font-family:ui-monospace,monospace;display:flex;
min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;text-align:center}
code{color:#fff}</style></head><body><div>
<h1>Acceso protegido</h1>
<p>Este equipo requiere token. Abre el enlace que te dio el instalador<br>
(o anade <code>?t=TU_TOKEN</code> a la direccion).</p>
</div></body></html>`
