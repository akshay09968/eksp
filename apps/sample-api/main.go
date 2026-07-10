// sample-api: the platform's scale-demo workload. One binary, two roles:
//
//	ROLE=api    — edge service; /chain fans out to the worker (mesh east-west)
//	ROLE=worker — backend compute; /work burns tunable CPU/allocation
//
// The part worth reading is the shutdown path: SIGTERM → readiness fails →
// keep serving while endpoints/ALB deregister (SHUTDOWN_DELAY) → drain
// in-flight → exit. Distroless images have no shell for a preStop sleep, so
// the app owns its drain; terminationGracePeriodSeconds (45s) >
// SHUTDOWN_DELAY (15s) + ALB deregistration delay (30s worst case).
package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	maxWorkMs     = 5000
	maxWorkKb     = 1024
	maxChainCalls = 8
)

type config struct {
	Port          string
	Role          string // api | worker
	WorkerURL     string
	Version       string
	ShutdownDelay time.Duration
}

func configFromEnv() config {
	delay := 15 * time.Second
	if v := os.Getenv("SHUTDOWN_DELAY"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			delay = d
		}
	}
	cfg := config{
		Port:          envOr("PORT", "8080"),
		Role:          envOr("ROLE", "api"),
		WorkerURL:     os.Getenv("WORKER_URL"),
		Version:       envOr("VERSION", "dev"),
		ShutdownDelay: delay,
	}
	return cfg
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

type app struct {
	cfg      config
	ready    atomic.Bool
	registry *prometheus.Registry
	requests *prometheus.CounterVec
	duration *prometheus.HistogramVec
	inflight prometheus.Gauge
	client   *http.Client
	log      *slog.Logger
}

func newApp(cfg config) *app {
	reg := prometheus.NewRegistry()

	a := &app{
		cfg:      cfg,
		registry: reg,
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "HTTP requests by route, method and status code.",
		}, []string{"route", "method", "code"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Request latency by route.",
			Buckets: []float64{.001, .0025, .005, .01, .025, .05, .1, .15, .25, .5, 1, 2.5},
		}, []string{"route", "method", "code"}),
		inflight: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "http_requests_in_flight",
			Help: "Requests currently being served.",
		}),
		// Tuned transport: at thousands of RPS the default 2 idle conns per
		// host forces constant reconnects (and conntrack churn) on the
		// api→worker path.
		client: &http.Client{
			Timeout: 2 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        512,
				MaxIdleConnsPerHost: 256,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		log: slog.New(slog.NewJSONHandler(os.Stdout, nil)),
	}

	reg.MustRegister(a.requests, a.duration, a.inflight)
	return a
}

// beginDrain flips readiness off; the readiness probe (period 5s, failures 2)
// pulls the pod from endpoints while it keeps serving.
func (a *app) beginDrain() {
	a.ready.Store(false)
}

func (a *app) routes() http.Handler {
	mux := http.NewServeMux()

	mux.Handle("GET /", a.instrument("/", a.handleRoot))
	mux.Handle("GET /work", a.instrument("/work", a.handleWork))
	if a.cfg.Role == "api" {
		mux.Handle("GET /chain", a.instrument("/chain", a.handleChain))
	}

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "ok")
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if a.ready.Load() {
			w.WriteHeader(http.StatusOK)
			fmt.Fprint(w, "ready")
			return
		}
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprint(w, "draining")
	})
	mux.Handle("GET /metrics", promhttp.HandlerFor(a.registry, promhttp.HandlerOpts{}))

	return mux
}

// instrument wraps a handler with the RED metrics and panic recovery. Routes
// are static strings — never raw URL paths — to keep label cardinality bounded.
func (a *app) instrument(route string, next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		a.inflight.Inc()
		defer a.inflight.Dec()

		sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		defer func() {
			if rec := recover(); rec != nil {
				a.log.Error("panic", "route", route, "err", fmt.Sprint(rec))
				http.Error(sw, "internal error", http.StatusInternalServerError)
			}
			code := strconv.Itoa(sw.code)
			a.requests.WithLabelValues(route, r.Method, code).Inc()
			a.duration.WithLabelValues(route, r.Method, code).Observe(time.Since(start).Seconds())
		}()

		next(sw, r)
	})
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (w *statusWriter) WriteHeader(code int) {
	w.code = code
	w.ResponseWriter.WriteHeader(code)
}

func (a *app) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	host, _ := os.Hostname()
	writeJSON(w, http.StatusOK, map[string]string{
		"service":  "sample-api",
		"role":     a.cfg.Role,
		"version":  a.cfg.Version,
		"hostname": host,
	})
}

// handleWork simulates request cost: ?ms= busy-work duration, ?kb= allocation.
// Both are clamped — this endpoint is exposed to load generators, and an
// unclamped value would be a self-DoS button.
func (a *app) handleWork(w http.ResponseWriter, r *http.Request) {
	ms := clampQueryInt(r, "ms", 0, maxWorkMs)
	kb := clampQueryInt(r, "kb", 0, maxWorkKb)

	buf := make([]byte, kb*1024)
	sum := sha256.Sum256(buf)

	deadline := time.Now().Add(time.Duration(ms) * time.Millisecond)
	for time.Now().Before(deadline) {
		sum = sha256.Sum256(sum[:]) // burn CPU, not sleep — sleeps don't scale HPAs
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"role":   a.cfg.Role,
		"ms":     ms,
		"kb":     kb,
		"digest": fmt.Sprintf("%x", sum[:4]),
	})
}

// handleChain (api only) fans out to the worker — the traffic the mesh secures
// and the waypoint applies retry/timeout policy to.
func (a *app) handleChain(w http.ResponseWriter, r *http.Request) {
	if a.cfg.WorkerURL == "" {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"error": "WORKER_URL not configured",
		})
		return
	}
	calls := clampQueryInt(r, "calls", 1, maxChainCalls)
	workMs := clampQueryInt(r, "ms", 0, maxWorkMs)

	type result struct {
		Status int    `json:"status"`
		Err    string `json:"error,omitempty"`
	}
	results := make([]result, calls)
	done := make(chan struct{})

	for i := 0; i < calls; i++ {
		go func(i int) {
			defer func() { done <- struct{}{} }()
			url := fmt.Sprintf("%s/work?ms=%d", a.cfg.WorkerURL, workMs)
			req, _ := http.NewRequestWithContext(r.Context(), http.MethodGet, url, nil)
			resp, err := a.client.Do(req)
			if err != nil {
				results[i] = result{Status: 0, Err: err.Error()}
				return
			}
			defer resp.Body.Close()
			results[i] = result{Status: resp.StatusCode}
		}(i)
	}
	for i := 0; i < calls; i++ {
		<-done
	}

	status := http.StatusOK
	for _, res := range results {
		if res.Status != http.StatusOK {
			status = http.StatusBadGateway
			break
		}
	}
	writeJSON(w, status, map[string]any{
		"role":    a.cfg.Role,
		"calls":   calls,
		"results": results,
	})
}

func clampQueryInt(r *http.Request, key string, min, max int) int {
	v, err := strconv.Atoi(r.URL.Query().Get(key))
	if err != nil || v < min {
		if key == "calls" {
			return min // a chain with zero calls is meaningless
		}
		return 0
	}
	if v > max {
		return max
	}
	return v
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func main() {
	cfg := configFromEnv()
	a := newApp(cfg)
	a.ready.Store(true)

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           a.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       120 * time.Second, // > ALB idle timeout (60s): the
		// backend must never close a connection the ALB still considers open.
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	go func() {
		a.log.Info("listening", "port", cfg.Port, "role", cfg.Role, "version", cfg.Version)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			a.log.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()

	// Drain sequence — see the package comment.
	a.log.Info("SIGTERM: failing readiness, serving through deregistration", "delay", cfg.ShutdownDelay.String())
	a.beginDrain()
	time.Sleep(cfg.ShutdownDelay)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		a.log.Error("forced shutdown with requests in flight", "err", err)
	}
	a.log.Info("drained cleanly")
}
