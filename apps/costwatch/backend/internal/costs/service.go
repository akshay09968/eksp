package costs

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/costexplorer"
	cetypes "github.com/aws/aws-sdk-go-v2/service/costexplorer/types"
)

// maxGroups caps distinct series returned to the UI; everything past it folds
// into "Other" (a categorical palette stops being readable past ~a dozen hues).
const maxGroups = 12

type Service struct {
	api   CostExplorerAPI
	cache *cache
	now   func() time.Time
}

type Option func(*Service)

// WithTTL sets the cache TTL; 0 disables caching (used by tests/demo checks).
func WithTTL(d time.Duration) Option {
	return func(s *Service) { s.cache = newCache(d) }
}

// WithNow pins the clock — Summary math is date-window arithmetic and must be
// testable on a fixed day.
func WithNow(fn func() time.Time) Option {
	return func(s *Service) { s.now = fn }
}

func NewService(api CostExplorerAPI, opts ...Option) *Service {
	s := &Service{
		api:   api,
		cache: newCache(6 * time.Hour),
		now:   time.Now,
	}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

func (s *Service) CacheStats() CacheStats { return s.cache.stats() }

// ---------------------------------------------------------------------------
// Costs
// ---------------------------------------------------------------------------

func (s *Service) Costs(ctx context.Context, q Query) (Series, error) {
	if err := q.normalize(); err != nil {
		return Series{}, err
	}

	key := fmt.Sprintf("costs|%s|%s|%d", q.Granularity, q.GroupBy, q.Days)
	val, cached, err := s.cache.do(key, func() (any, error) {
		return s.fetchCosts(ctx, q)
	})
	if err != nil {
		return Series{}, err
	}
	series := val.(Series)
	series.Cached = cached
	return series, nil
}

func (q *Query) normalize() error {
	switch q.Granularity {
	case Hourly, Daily, Monthly:
	default:
		return fmt.Errorf("unsupported granularity %q (HOURLY|DAILY|MONTHLY)", q.Granularity)
	}

	if !ValidGroupBys[q.GroupBy] && !strings.HasPrefix(q.GroupBy, "TAG:") {
		return fmt.Errorf("unsupported groupBy %q", q.GroupBy)
	}

	switch q.Granularity {
	case Hourly:
		q.Days = clamp(q.Days, 1, 14) // CE hard limit for hourly data
	case Daily:
		q.Days = clamp(q.Days, 1, 365)
		if q.Days == 1 {
			q.Days = 30
		}
	case Monthly:
		q.Days = clamp(q.Days, 30, 390)
	}
	return nil
}

func clamp(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func (s *Service) fetchCosts(ctx context.Context, q Query) (Series, error) {
	now := s.now().UTC()
	var start, end string
	switch q.Granularity {
	case Hourly:
		e := now.Truncate(time.Hour)
		st := e.Add(-time.Duration(q.Days) * 24 * time.Hour)
		start, end = st.Format(time.RFC3339), e.Format(time.RFC3339)
	case Daily:
		start = now.AddDate(0, 0, -q.Days).Format("2006-01-02")
		end = now.Format("2006-01-02")
	case Monthly:
		months := q.Days / 30
		first := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
		start = first.AddDate(0, -(months - 1), 0).Format("2006-01-02")
		end = now.Format("2006-01-02")
	}

	groupDef := cetypes.GroupDefinition{
		Type: cetypes.GroupDefinitionTypeDimension,
		Key:  aws.String(q.GroupBy),
	}
	if tag, ok := strings.CutPrefix(q.GroupBy, "TAG:"); ok {
		groupDef = cetypes.GroupDefinition{
			Type: cetypes.GroupDefinitionTypeTag,
			Key:  aws.String(tag),
		}
	}

	input := &costexplorer.GetCostAndUsageInput{
		TimePeriod:  &cetypes.DateInterval{Start: aws.String(start), End: aws.String(end)},
		Granularity: cetypes.Granularity(q.Granularity),
		Metrics:     []string{"UnblendedCost"},
		GroupBy:     []cetypes.GroupDefinition{groupDef},
	}

	var results []cetypes.ResultByTime
	for {
		out, err := s.api.GetCostAndUsage(ctx, input)
		if err != nil {
			return Series{}, mapCEError(err)
		}
		results = append(results, out.ResultsByTime...)
		if out.NextPageToken == nil || *out.NextPageToken == "" {
			break
		}
		input.NextPageToken = out.NextPageToken
	}

	return s.aggregate(results), nil
}

func (s *Service) aggregate(results []cetypes.ResultByTime) Series {
	series := Series{Currency: "USD", FetchedAt: s.now().UTC()}
	groupIdx := map[string]int{}

	for _, r := range results {
		if r.TimePeriod == nil || r.TimePeriod.Start == nil {
			continue
		}
		series.Times = append(series.Times, *r.TimePeriod.Start)
		t := len(series.Times) - 1

		for _, g := range r.Groups {
			if len(g.Keys) == 0 {
				continue
			}
			key := g.Keys[0]
			metric, ok := g.Metrics["UnblendedCost"]
			if !ok || metric.Amount == nil {
				continue
			}
			amount, err := strconv.ParseFloat(*metric.Amount, 64)
			if err != nil {
				continue
			}
			if metric.Unit != nil && *metric.Unit != "" {
				series.Currency = *metric.Unit
			}

			idx, ok := groupIdx[key]
			if !ok {
				idx = len(series.Groups)
				groupIdx[key] = idx
				series.Groups = append(series.Groups, GroupSeries{Key: key})
			}
			for len(series.Groups[idx].Values) < t {
				series.Groups[idx].Values = append(series.Groups[idx].Values, 0)
			}
			series.Groups[idx].Values = append(series.Groups[idx].Values, amount)
			series.Groups[idx].Total += amount
		}
	}

	// zero-fill trailing periods so every series aligns with Times
	for i := range series.Groups {
		for len(series.Groups[i].Values) < len(series.Times) {
			series.Groups[i].Values = append(series.Groups[i].Values, 0)
		}
		series.Total += series.Groups[i].Total
	}

	sort.SliceStable(series.Groups, func(i, j int) bool {
		return series.Groups[i].Total > series.Groups[j].Total
	})

	if len(series.Groups) > maxGroups {
		other := GroupSeries{Key: "Other", Values: make([]float64, len(series.Times))}
		for _, g := range series.Groups[maxGroups:] {
			for t, v := range g.Values {
				other.Values[t] += v
			}
			other.Total += g.Total
		}
		series.Groups = append(series.Groups[:maxGroups:maxGroups], other)
	}

	return series
}

func mapCEError(err error) error {
	msg := err.Error()
	if strings.Contains(strings.ToLower(msg), "hourly") {
		return fmt.Errorf("%w: %v", ErrHourlyNotEnabled, err)
	}
	return err
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

func (s *Service) Summary(ctx context.Context) (Summary, error) {
	val, cached, err := s.cache.do("summary", func() (any, error) {
		return s.fetchSummary(ctx)
	})
	if err != nil {
		return Summary{}, err
	}
	sum := val.(Summary)
	sum.Cached = cached
	return sum, nil
}

func (s *Service) fetchSummary(ctx context.Context) (Summary, error) {
	now := s.now().UTC()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	prevStart := monthStart.AddDate(0, -1, 0)
	dayOffset := int(now.Sub(monthStart).Hours() / 24)
	prevEnd := prevStart.AddDate(0, 0, dayOffset)
	nextMonth := monthStart.AddDate(0, 1, 0)

	current, err := s.byService(ctx, monthStart, now)
	if err != nil {
		return Summary{}, err
	}
	previous, err := s.byService(ctx, prevStart, prevEnd)
	if err != nil {
		return Summary{}, err
	}

	sum := Summary{Currency: "USD", FetchedAt: now}
	for _, v := range current {
		sum.MonthToDate += v
	}
	for _, v := range previous {
		sum.PrevMonthToDate += v
	}
	if sum.PrevMonthToDate > 0 {
		sum.DeltaPct = (sum.MonthToDate - sum.PrevMonthToDate) / sum.PrevMonthToDate * 100
	}

	// Forecast to month end (skip when the API has nothing to extrapolate —
	// e.g. brand-new accounts).
	fc, err := s.api.GetCostForecast(ctx, &costexplorer.GetCostForecastInput{
		TimePeriod: &cetypes.DateInterval{
			Start: aws.String(now.Format("2006-01-02")),
			End:   aws.String(nextMonth.Format("2006-01-02")),
		},
		Metric:      cetypes.MetricUnblendedCost,
		Granularity: cetypes.GranularityMonthly,
	})
	if err == nil && fc.Total != nil && fc.Total.Amount != nil {
		if v, perr := strconv.ParseFloat(*fc.Total.Amount, 64); perr == nil {
			sum.ForecastMonthEnd = v
		}
	}

	// Top movers by absolute delta vs the same window last month.
	seen := map[string]bool{}
	for k := range current {
		seen[k] = true
	}
	for k := range previous {
		seen[k] = true
	}
	for svc := range seen {
		sum.TopMovers = append(sum.TopMovers, Mover{
			Service:  svc,
			Current:  current[svc],
			Previous: previous[svc],
			Delta:    current[svc] - previous[svc],
		})
	}
	sort.Slice(sum.TopMovers, func(i, j int) bool {
		return abs(sum.TopMovers[i].Delta) > abs(sum.TopMovers[j].Delta)
	})
	if len(sum.TopMovers) > 5 {
		sum.TopMovers = sum.TopMovers[:5]
	}

	return sum, nil
}

func (s *Service) byService(ctx context.Context, start, end time.Time) (map[string]float64, error) {
	input := &costexplorer.GetCostAndUsageInput{
		TimePeriod: &cetypes.DateInterval{
			Start: aws.String(start.Format("2006-01-02")),
			End:   aws.String(end.Format("2006-01-02")),
		},
		Granularity: cetypes.GranularityMonthly,
		Metrics:     []string{"UnblendedCost"},
		GroupBy: []cetypes.GroupDefinition{{
			Type: cetypes.GroupDefinitionTypeDimension,
			Key:  aws.String("SERVICE"),
		}},
	}

	totals := map[string]float64{}
	for {
		out, err := s.api.GetCostAndUsage(ctx, input)
		if err != nil {
			return nil, mapCEError(err)
		}
		for _, r := range out.ResultsByTime {
			for _, g := range r.Groups {
				if len(g.Keys) == 0 {
					continue
				}
				if m, ok := g.Metrics["UnblendedCost"]; ok && m.Amount != nil {
					if v, err := strconv.ParseFloat(*m.Amount, 64); err == nil {
						totals[g.Keys[0]] += v
					}
				}
			}
		}
		if out.NextPageToken == nil || *out.NextPageToken == "" {
			break
		}
		input.NextPageToken = out.NextPageToken
	}
	return totals, nil
}

func abs(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}
