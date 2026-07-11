package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/akshaydeshpande/eksp/apps/costwatch/internal/costs"
)

func newTestServer() *Server {
	svc := costs.NewService(costs.NewDemoClient())
	dist := fstest.MapFS{
		"index.html":    {Data: []byte("<!doctype html><title>costwatch</title>")},
		"assets/app.js": {Data: []byte("// bundle")},
	}
	return New(svc, true, dist)
}

func get(t *testing.T, s *Server, path string) *httptest.ResponseRecorder {
	t.Helper()
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
	return rr
}

func TestSummaryReturnsShape(t *testing.T) {
	rr := get(t, newTestServer(), "/api/summary")
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d body=%s", rr.Code, rr.Body.String())
	}
	var sum costs.Summary
	if err := json.Unmarshal(rr.Body.Bytes(), &sum); err != nil {
		t.Fatalf("bad json: %v", err)
	}
	if sum.MonthToDate <= 0 || len(sum.TopMovers) == 0 {
		t.Fatalf("summary looks empty: %+v", sum)
	}
}

func TestCostsValidatesParams(t *testing.T) {
	s := newTestServer()

	rr := get(t, s, "/api/costs?granularity=fortnightly")
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("bad granularity status = %d, want 400", rr.Code)
	}

	rr = get(t, s, "/api/costs?groupBy=EVIL")
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("bad groupBy status = %d, want 400", rr.Code)
	}

	rr = get(t, s, "/api/costs?days=NaN")
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("bad days status = %d, want 400", rr.Code)
	}
}

func TestCostsDefaultsToDailyByService(t *testing.T) {
	rr := get(t, newTestServer(), "/api/costs")
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d body=%s", rr.Code, rr.Body.String())
	}
	var series costs.Series
	if err := json.Unmarshal(rr.Body.Bytes(), &series); err != nil {
		t.Fatalf("bad json: %v", err)
	}
	if len(series.Times) != 30 || len(series.Groups) == 0 {
		t.Fatalf("default series wrong: %d times %d groups", len(series.Times), len(series.Groups))
	}
}

func TestHealthReportsDemoAndCache(t *testing.T) {
	rr := get(t, newTestServer(), "/api/health")
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d", rr.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("bad json: %v", err)
	}
	if body["demo"] != true || body["status"] != "ok" {
		t.Fatalf("health = %v", body)
	}
}

func TestSPAFallbackServesIndex(t *testing.T) {
	s := newTestServer()

	// real asset served as-is
	rr := get(t, s, "/assets/app.js")
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), "bundle") {
		t.Fatalf("asset: %d %q", rr.Code, rr.Body.String())
	}

	// client-side route falls back to index.html
	rr = get(t, s, "/explore")
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), "costwatch") {
		t.Fatalf("spa fallback: %d %q", rr.Code, rr.Body.String())
	}
}

func TestMetricsExposed(t *testing.T) {
	s := newTestServer()
	get(t, s, "/api/health") // generate a sample
	rr := get(t, s, "/metrics")
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), "http_requests_total") {
		t.Fatalf("metrics: %d", rr.Code)
	}
}
