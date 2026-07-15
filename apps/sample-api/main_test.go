package main

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func newTestApp(role, workerURL string) *app {
	a := newApp(config{
		Role:          role,
		WorkerURL:     workerURL,
		Version:       "test",
		ShutdownDelay: 10 * time.Millisecond,
	})
	a.ready.Store(true)
	return a
}

func TestRootReportsRoleAndVersion(t *testing.T) {
	a := newTestApp("api", "")
	rr := httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/", nil))

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rr.Code)
	}
	var body map[string]string
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if body["role"] != "api" || body["version"] != "test" {
		t.Fatalf("body = %v, want role=api version=test", body)
	}
}

func TestWorkClampsInputs(t *testing.T) {
	a := newTestApp("worker", "")

	tests := []struct {
		name  string
		query string
	}{
		{"negative ms", "/work?ms=-5"},
		{"huge ms is clamped not honored", "/work?ms=999999"},
		{"garbage kb", "/work?kb=banana"},
		{"huge kb clamped", "/work?kb=999999"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			start := time.Now()
			rr := httptest.NewRecorder()
			a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, tt.query, nil))
			if rr.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200", rr.Code)
			}
			// maxWorkMs is 5000; anything clamped must respond well before that
			// in tests (clamp ceiling applies, garbage becomes 0).
			if elapsed := time.Since(start); elapsed > 6*time.Second {
				t.Fatalf("work took %v — clamp failed", elapsed)
			}
			var body map[string]any
			if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
				t.Fatalf("invalid json: %v", err)
			}
			if ms, ok := body["ms"].(float64); !ok || ms < 0 || ms > 5000 {
				t.Fatalf("ms = %v, want 0..5000", body["ms"])
			}
		})
	}
}

func TestChainFansOutToWorker(t *testing.T) {
	var calls atomic.Int64
	worker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		fmt.Fprint(w, `{"ok":true}`)
	}))
	defer worker.Close()

	a := newTestApp("api", worker.URL)
	rr := httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/chain?calls=3", nil))

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", rr.Code, rr.Body.String())
	}
	if got := calls.Load(); got != 3 {
		t.Fatalf("worker called %d times, want 3", got)
	}
}

func TestChainRejectedOnWorkerRole(t *testing.T) {
	a := newTestApp("worker", "")
	rr := httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/chain", nil))

	if rr.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 (chain is api-only)", rr.Code)
	}
}

func TestChainClampsCallCount(t *testing.T) {
	var calls atomic.Int64
	worker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		fmt.Fprint(w, `{"ok":true}`)
	}))
	defer worker.Close()

	a := newTestApp("api", worker.URL)
	rr := httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/chain?calls=9999", nil))

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rr.Code)
	}
	if got := calls.Load(); got != maxChainCalls {
		t.Fatalf("worker called %d times, want clamp at %d", got, maxChainCalls)
	}
}

func TestReadyzFollowsDrainState(t *testing.T) {
	a := newTestApp("api", "")

	rr := httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("ready status = %d, want 200", rr.Code)
	}

	a.beginDrain()

	rr = httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rr.Code != http.StatusServiceUnavailable {
		t.Fatalf("draining status = %d, want 503", rr.Code)
	}

	// healthz must stay green during drain — only readiness gates traffic.
	rr = httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("healthz during drain = %d, want 200", rr.Code)
	}
}

func TestConfigFromEnv(t *testing.T) {
	t.Setenv("PORT", "9999")
	t.Setenv("ROLE", "worker")
	t.Setenv("WORKER_URL", "http://w.example")
	t.Setenv("VERSION", "v9")
	t.Setenv("SHUTDOWN_DELAY", "3s")

	cfg := configFromEnv()
	if cfg.Port != "9999" || cfg.Role != "worker" || cfg.WorkerURL != "http://w.example" ||
		cfg.Version != "v9" || cfg.ShutdownDelay != 3*time.Second {
		t.Fatalf("cfg = %+v", cfg)
	}

	// garbage duration falls back to the default, never panics or zeroes
	t.Setenv("SHUTDOWN_DELAY", "banana")
	if got := configFromEnv().ShutdownDelay; got != 15*time.Second {
		t.Fatalf("bad SHUTDOWN_DELAY fallback = %v, want 15s", got)
	}
}

func TestInstrumentRecoversPanics(t *testing.T) {
	a := newTestApp("api", "")
	h := a.instrument("/boom", func(http.ResponseWriter, *http.Request) {
		panic("kaboom")
	})

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/boom", nil)) // must not crash the test

	// the panic is converted to a 500 and still lands in the metrics
	rr = httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if !strings.Contains(rr.Body.String(), `route="/boom"`) {
		t.Fatal("panicking request not recorded in http_requests_total")
	}
}

// The drain contract end to end: readiness fails immediately, in-flight
// requests finish, and shutdown waits at least ShutdownDelay before closing.
func TestShutdownDrainsInflightRequests(t *testing.T) {
	a := newTestApp("api", "")
	a.cfg.ShutdownDelay = 50 * time.Millisecond

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := &http.Server{Handler: a.routes()}
	go func() { _ = srv.Serve(ln) }()
	base := "http://" + ln.Addr().String()

	// in-flight slow request racing the shutdown
	type result struct {
		code int
		err  error
	}
	done := make(chan result, 1)
	go func() {
		resp, err := http.Get(base + "/work?ms=200")
		if err != nil {
			done <- result{0, err}
			return
		}
		defer resp.Body.Close()
		done <- result{resp.StatusCode, nil}
	}()

	time.Sleep(20 * time.Millisecond) // let the slow request start

	start := time.Now()
	a.shutdown(srv)
	elapsed := time.Since(start)

	if elapsed < a.cfg.ShutdownDelay {
		t.Fatalf("shutdown returned in %v — did not honor the %v drain delay", elapsed, a.cfg.ShutdownDelay)
	}
	if a.ready.Load() {
		t.Fatal("still ready after shutdown — readiness must fail during drain")
	}
	r := <-done
	if r.err != nil || r.code != http.StatusOK {
		t.Fatalf("in-flight request during drain: code=%d err=%v — drain must not drop it", r.code, r.err)
	}

	// after shutdown completes, new connections are refused
	if _, err := http.Get(base + "/healthz"); err == nil {
		t.Fatal("server still accepting connections after Shutdown returned")
	}
}

func TestMetricsExposeRequestCounter(t *testing.T) {
	a := newTestApp("api", "")

	// generate one request so the counter exists
	rr := httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/", nil))

	rr = httptest.NewRecorder()
	a.routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("metrics status = %d, want 200", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), "http_requests_total") {
		t.Fatal("metrics output missing http_requests_total")
	}
	if !strings.Contains(rr.Body.String(), "http_request_duration_seconds") {
		t.Fatal("metrics output missing http_request_duration_seconds histogram")
	}
}
