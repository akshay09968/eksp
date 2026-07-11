package api

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/akshaydeshpande/eksp/apps/costwatch/internal/costs"
)

func (s *Server) handleSummary(w http.ResponseWriter, r *http.Request) {
	sum, err := s.svc.Summary(r.Context())
	if err != nil {
		s.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, sum)
}

func (s *Server) handleCosts(w http.ResponseWriter, r *http.Request) {
	q := costs.Query{
		Granularity: costs.Granularity(strings.ToUpper(r.URL.Query().Get("granularity"))),
		GroupBy:     r.URL.Query().Get("groupBy"),
	}
	if q.Granularity == "" {
		q.Granularity = costs.Daily
	}
	if q.GroupBy == "" {
		q.GroupBy = "SERVICE"
	}
	if days := r.URL.Query().Get("days"); days != "" {
		v, err := strconv.Atoi(days)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, errorBody{Error: "days must be an integer"})
			return
		}
		q.Days = v
	}

	series, err := s.svc.Costs(r.Context(), q)
	if err != nil {
		s.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, series)
}

func (s *Server) writeServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, costs.ErrHourlyNotEnabled):
		// 409: the request is fine, the account state isn't — and the fix is
		// actionable, so say it.
		writeJSON(w, http.StatusConflict, errorBody{
			Error: "hourly data not enabled for this account",
			Hint:  "Billing console → Cost Management preferences → enable 'Hourly and Resource Level Data' (extra AWS charge applies), or use daily granularity",
		})
	case strings.Contains(err.Error(), "unsupported"):
		writeJSON(w, http.StatusBadRequest, errorBody{Error: err.Error()})
	case strings.Contains(err.Error(), "AccessDenied"), strings.Contains(err.Error(), "no EC2 IMDS role"),
		strings.Contains(err.Error(), "failed to retrieve credentials"):
		writeJSON(w, http.StatusForbidden, errorBody{
			Error: "cannot reach Cost Explorer with the pod's credentials",
			Hint:  "check the Pod Identity association (terraform/envs/*/main.tf) maps namespace costwatch / SA costwatch to the CE read role — or run with -demo",
		})
	default:
		writeJSON(w, http.StatusBadGateway, errorBody{Error: err.Error()})
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"demo":    s.demo,
		"uptime":  time.Since(s.started).Round(time.Second).String(),
		"cache":   s.svc.CacheStats(),
		"version": Version,
	})
}

// Version is stamped via -ldflags at build time.
var Version = "dev"
