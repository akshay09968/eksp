// Package costs turns Cost Explorer's paginated, stringly-typed responses into
// the small set of shapes the UI actually renders. The AWS client hides behind
// CostExplorerAPI so every aggregation path is unit-testable offline — and so
// demo mode can implement the same interface with synthetic data.
package costs

import (
	"errors"
	"time"
)

type Granularity string

const (
	Hourly  Granularity = "HOURLY"
	Daily   Granularity = "DAILY"
	Monthly Granularity = "MONTHLY"
)

// GroupBy values map to CE dimensions; "TAG:<key>" selects a cost-allocation tag.
var ValidGroupBys = map[string]bool{
	"SERVICE":        true,
	"LINKED_ACCOUNT": true,
	"REGION":         true,
	"USAGE_TYPE":     true,
	"RESOURCE_ID":    true,
}

// ErrHourlyNotEnabled surfaces the CE opt-in requirement as an actionable
// condition instead of a raw ValidationException.
var ErrHourlyNotEnabled = errors.New(
	"hourly granularity requires the 'Hourly and Resource Level Data' opt-in " +
		"(Billing → Cost Management preferences); it also limits history to 14 days")

type Query struct {
	Granularity Granularity
	GroupBy     string
	// Days of history. Clamped per granularity: HOURLY ≤ 14, DAILY ≤ 365,
	// MONTHLY expressed in months (Days/30).
	Days int
}

type GroupSeries struct {
	Key    string    `json:"key"`
	Values []float64 `json:"values"`
	Total  float64   `json:"total"`
}

type Series struct {
	Times     []string      `json:"times"` // period start timestamps, RFC3339 date or datetime
	Groups    []GroupSeries `json:"groups"`
	Total     float64       `json:"total"`
	Currency  string        `json:"currency"`
	FetchedAt time.Time     `json:"fetchedAt"`
	Cached    bool          `json:"cached"`
}

type Mover struct {
	Service  string  `json:"service"`
	Current  float64 `json:"current"`
	Previous float64 `json:"previous"`
	Delta    float64 `json:"delta"`
}

type Summary struct {
	MonthToDate      float64   `json:"monthToDate"`
	ForecastMonthEnd float64   `json:"forecastMonthEnd"`
	PrevMonthToDate  float64   `json:"prevMonthToDate"`
	DeltaPct         float64   `json:"deltaPct"` // MTD vs same window last month
	Currency         string    `json:"currency"`
	TopMovers        []Mover   `json:"topMovers"`
	FetchedAt        time.Time `json:"fetchedAt"`
	Cached           bool      `json:"cached"`
}
