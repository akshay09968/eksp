// Package api wires the costs service to HTTP: JSON endpoints under /api,
// Prometheus metrics, and the embedded SPA with index-fallback routing.
package api

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/akshaydeshpande/eksp/apps/costwatch/internal/costs"
)

type Server struct {
	svc      *costs.Service
	demo     bool
	started  time.Time
	registry *prometheus.Registry
	requests *prometheus.CounterVec
	duration *prometheus.HistogramVec
	static   http.Handler
	dist     fs.FS
}

func New(svc *costs.Service, demo bool, dist fs.FS) *Server {
	reg := prometheus.NewRegistry()
	s := &Server{
		svc:      svc,
		demo:     demo,
		started:  time.Now(),
		registry: reg,
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "HTTP requests by route, method and status code.",
		}, []string{"route", "method", "code"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Request latency by route.",
			Buckets: prometheus.DefBuckets,
		}, []string{"route", "method", "code"}),
		static: http.FileServer(http.FS(dist)),
		dist:   dist,
	}
	reg.MustRegister(s.requests, s.duration)
	return s
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.Handle("GET /api/summary", s.instrument("/api/summary", s.handleSummary))
	mux.Handle("GET /api/costs", s.instrument("/api/costs", s.handleCosts))
	mux.Handle("GET /api/health", s.instrument("/api/health", s.handleHealth))
	mux.Handle("GET /metrics", promhttp.HandlerFor(s.registry, promhttp.HandlerOpts{}))
	mux.Handle("GET /", s.instrument("/static", s.handleStatic))

	return mux
}

// handleStatic serves the embedded SPA; unknown paths fall back to index.html
// so client-side views survive a refresh. A binary built before the frontend
// (fresh clone) gets an actionable hint page instead of a 404.
func (s *Server) handleStatic(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	if path != "/" {
		if f, err := s.dist.Open(path[1:]); err == nil {
			f.Close()
			s.static.ServeHTTP(w, r)
			return
		}
	}
	if f, err := s.dist.Open("index.html"); err == nil {
		f.Close()
		r.URL.Path = "/"
		s.static.ServeHTTP(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(`<!doctype html><title>costwatch</title><body style="font-family:monospace;padding:3rem"><p>costwatch API is up (<a href="/api/health">/api/health</a>), but this binary was built without the UI.<br>Run <b>make frontend-build</b> then rebuild the Go binary.</p></body>`))
}

func (s *Server) instrument(route string, next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		next(sw, r)
		code := strconv.Itoa(sw.code)
		s.requests.WithLabelValues(route, r.Method, code).Inc()
		s.duration.WithLabelValues(route, r.Method, code).Observe(time.Since(start).Seconds())
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

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

type errorBody struct {
	Error string `json:"error"`
	Hint  string `json:"hint,omitempty"`
}
